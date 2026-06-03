# 03 — Self-Hosted Notary (для `api.github.com` whitelist + Tier-1)

**Когда нужно.** Item ⑧ PLAN.md. wiring real verifier. PSE's hosted notary whitelists только specific domains. Для arbitrary Tier-1 targets (api.github.com, api.strava.com, etc) нужен self-host.

**Что получишь.** Docker compose stack с notary-server (TCP) + websockify (browser WS↔TCP proxy), whitelist'нутый под все Tier-1 hosts.

**Время.** ~30-60 минут first time (включая build), ~5 минут для restart.

**Prerequisites.**
- Docker Desktop / Docker Engine installed
- Linux box или Mac для running (production. AWS / Fly.io / Hetzner)
- Domain или IP для notary (dev. `notary.local`, prod. `verifier.rep.xyz`)

---

## Architecture refresher

```
┌─────────────────┐    WebSocket    ┌──────────────┐    TCP TLS    ┌──────────────┐
│  iOS Prover     │────────────────▶│  Verifier    │──────────────▶│ api.github.  │
│  (REP app)      │   (proxy mode)  │  (notary)    │   (encrypted) │ com          │
└─────────────────┘                 └──────────────┘                └──────────────┘
                                          │
                                          ▼
                                    [whitelist check.
                                     api.github.com OK?]
```

Verifier opens TCP to target. Если target не в whitelist — request rejected. Это **the IP tradeoff** про которое весь research.

## Source repo

```bash
git clone https://github.com/tlsnotary/tlsn.git
cd tlsn
```

Notary server лежит в `crates/notary-server/`.

---

## Steps

### 1. Build notary-server (native binary)

```bash
cd crates/notary-server
cargo build --release
```

Output. `target/release/notary-server`

Если хочешь сразу Docker — skip и иди в раздел "Docker" ниже.

### 2. Создай config с whitelist

В `crates/notary-server/config/config.yaml`:

```yaml
server:
  host: "0.0.0.0"
  port: 7047

notary:
  private_key:
    path: "./fixture/notary/notary.key"   # generate своим способом для prod

prover:
  proxy:
    enabled: true   # ✅ ENABLE proxy mode
    
  # Whitelist для proxy mode. ТОЛЬКО эти hosts разрешены
  allowed_domains:
    - "api.github.com"          # GitHub
    - "www.strava.com"          # Strava API host (хоть и /api/v3/ path)
    - "api.strava.com"          # Strava (если они когда-нибудь mig'нут)
    - "api.stackexchange.com"   # StackOverflow
    - "api.anthropic.com"       # Anthropic
    - "codeforces.com"          # Codeforces
    - "www.duolingo.com"        # Duolingo
    - "leetcode.com"            # LeetCode
    - "api.lu.ma"               # Luma
    
  # MPC mode — separate set of constraints
  mpc:
    enabled: true   # leave enabled as MPC fallback
    max_sent_data: 4096       # 4 KB
    max_recv_data: 16384      # 16 KB
    # для multi-endpoint kitchen-sink Strava up to 32-64 KB. tune later.

logging:
  level: "info"
  format: "json"

tls:
  enabled: true
  cert: "./fixture/tls/notary.crt"     # for dev. self-signed
  key: "./fixture/tls/notary.key"      # for prod. Let's Encrypt
```

### 3. Generate dev cert + key (для local testing)

```bash
mkdir -p fixture/tls
openssl req -x509 -newkey rsa:4096 -keyout fixture/tls/notary.key \
  -out fixture/tls/notary.crt -days 365 -nodes \
  -subj "/CN=notary.local"
```

⚠️ Self-signed cert работает только если iOS prover trust'ит его. Для simulator — добавь cert в Keychain. Для реального device — лучше использовать Let's Encrypt сразу.

### 4. Generate notary signing key

```bash
mkdir -p fixture/notary
# Используй ваш preferred way генерации ed25519 keypair, например:
ssh-keygen -t ed25519 -f fixture/notary/notary.key -N "" -C "rep-notary-dev"
# Или используй tlsn'овский cli если есть:
# cargo run --bin notary-keygen -- --out fixture/notary/notary.key
```

Public key (для verification proof'ов на стороне юзера) — `fixture/notary/notary.key.pub`.

### 5. Run native

```bash
./target/release/notary-server --config crates/notary-server/config/config.yaml
```

Test:
```bash
curl https://localhost:7047/health -k
# Должен return 200 OK
```

---

## Docker setup (recommended для deployment)

### Dockerfile (если нет в repo)

```dockerfile
FROM rust:1.96-slim AS builder
WORKDIR /app
COPY . .
RUN apt-get update && apt-get install -y pkg-config libssl-dev
RUN cargo build --release --bin notary-server

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/notary-server /usr/local/bin/notary-server
COPY config/ /etc/notary/config/
COPY fixture/ /etc/notary/fixture/
EXPOSE 7047
CMD ["notary-server", "--config", "/etc/notary/config/config.yaml"]
```

### docker-compose.yml

```yaml
version: '3.8'

services:
  notary:
    build: .
    container_name: rep-notary
    ports:
      - "7047:7047"
    volumes:
      - ./config:/etc/notary/config:ro
      - ./fixture:/etc/notary/fixture:ro
    restart: unless-stopped
    environment:
      - RUST_LOG=info
    healthcheck:
      test: ["CMD", "curl", "-fk", "https://localhost:7047/health"]
      interval: 30s
      timeout: 5s
      retries: 3

  # Optional. WebSocket↔TCP relay для browser MPC mode.
  # Для proxy mode не нужен — notary сам терминирует WS.
  # Если решишь support'ить browser MPC fallback (юзеры на iPad Safari вне native app):
  websockify:
    image: novnc/websockify:latest
    container_name: rep-websockify
    command: ["8080", "notary:7047"]
    ports:
      - "8080:8080"
    depends_on:
      - notary
    restart: unless-stopped
```

### Run

```bash
docker-compose up -d
docker-compose logs -f notary
```

Test:
```bash
curl -k https://localhost:7047/health
```

---

## Production deployment

### Quick path. Fly.io

```bash
fly launch --name rep-notary
# Edit fly.toml. expose port 7047, use Let's Encrypt cert
fly deploy
fly certs add verifier.rep.xyz
```

### Standard path. AWS / Hetzner / DigitalOcean

1. Provision VPS (1 vCPU / 2 GB RAM достаточно для dev/test, prod scale per traffic)
2. Install Docker + docker-compose
3. Setup Let's Encrypt cert через nginx-proxy или Caddy
4. Run docker-compose
5. DNS. `verifier.rep.xyz → <vps ip>`
6. Firewall. allow 443 in, all out

### Caddy config (auto Let's Encrypt)

```
verifier.rep.xyz {
    reverse_proxy localhost:7047
}
```

Caddy handles HTTPS cert renewal automatically.

---

## Wire в host-shell

В Swift кодом:

```swift
let verifierURL = URL(string: "wss://verifier.rep.xyz/notary")!
let prover = try await ProverSession.connect(
    verifier: verifierURL,
    roots: .mozillaWebPKI
)
```

Notary public key (для verifying proof'ов) надо bundle в app:
```swift
let notaryPublicKey = "ed25519:<base64 of fixture/notary/notary.key.pub>"
```

---

## Verify полный flow работает

1. Notary running на `wss://verifier.rep.xyz/notary` (или `wss://localhost:7047` для local dev)
2. С тестового account достань GitHub access token через cURL OAuth flow
3. В iOS app или через CLI utility сделай notarize request:

```bash
# pseudo-curl. реальный prover client — это xcframework calls
notary-client notarize \
  --target api.github.com:443 \
  --request "POST /graphql ..." \
  --auth "Bearer <token>" \
  --verifier wss://localhost:7047/notary
```

Если возвращает attestation — done.

---

## Common pitfalls

### "Allowed domains check failed"

Domain отсутствует в whitelist. Add в `config.yaml` под `prover.proxy.allowed_domains`.

### "TLS handshake error"

- Self-signed cert не trusted на device. Use Let's Encrypt or add cert to iOS Trust Store
- Hostname mismatch. cert generated для `notary.local`, но connecting к `localhost`. Regenerate cert с правильным CN

### "Out of memory" при MPC mode на больших requests

Verifier MPC needs RAM proportional к `max_sent_data` + `max_recv_data`. Bump VPS RAM или lower limits.

### Notary signing key compromised

Rotate. Generate new keypair, redeploy с new key, update bundled public key в next iOS app release. Old proofs остаются valid под старый key (если есть key history endpoint).

### "Connection refused" из iOS app в dev

iOS simulator не routes localhost ко host machine иногда. Use `host.docker.internal` или IP машины (`ipconfig getifaddr en0`) вместо `localhost`.

---

## Verify готов

```bash
docker-compose ps    # should show notary as healthy
curl -k https://localhost:7047/health    # 200 OK
```

И в Swift:
```swift
let session = try await ProverSession.connect(
    verifier: URL(string: "wss://localhost:7047/notary")!,
    roots: .mozillaWebPKI
)
print("Connected: \(session.isActive)")  // true
```

→ Готов wire-up real prover к real notary в host-shell.

## Что обновить после deployment

1. `test-kit/open-questions.md` → Q8 RESOLVED с verifier URL
2. `mobile-app/spec/SPEC.md` → Architecture diagram конкретный verifier URL
3. iOS app `Info.plist` или config → bundle notary public key для verification
