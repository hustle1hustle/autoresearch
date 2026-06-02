# Stage 4 — Hero Flow: "Prove your GitHub" (contributions)

**Why this hero.** Of the Stage 3 shortlist it has the best **wow-per-effort**: an **in-scope, plain-bearer OAuth token** (redact exactly one header), a **JSON GraphQL endpoint stable since 2016**, **clean ToS**, **proxy-mode-safe** (`api.github.com` rate-limits by token, not IP → the verifier's datacenter IP is fine), **Reclaim-proven**, and an audience — developers and AI-agent builders — that *is* REP's seed user. It is the lowest-risk way to demonstrate the whole thesis: *one tap-or-two → a portable, composable reputation node in the User Context Graph.*

**Claim we mint (v1):** *"GitHub user **`<login>`** made **`<N>`** contributions in 2026, per `api.github.com` on `<date>`."* Ownership is intrinsic because we query `viewer { … }` with the user's own token — the fact is about *whoever holds the token*, and we reveal their `login` to name them.

---

## 1. End-to-end flow

```
[REP app]                    [GitHub]                 [REP Verifier/Notary]      [api.github.com]
   |  tap "Prove your GitHub"   |                           |                          |
   |─ OAuth (PKCE, app-switch)─▶|                           |                          |
   |  Face ID; consent(1st only)|                           |                          |
   |◀── auth code ──────────────|                           |                          |
   |─ code→token (PKCE) ───────▶|  (token endpoint)         |                          |
   |◀── access_token (bearer) ──|                           |                          |
   |                                                        |                          |
   |── open TLSNotary session (WebSocket) ─────────────────▶|                          |
   |   prover: ProxyTlsConfig(server_name=api.github.com)   |                          |
   |                                                        |── TCP+TLS connect ──────▶|   ← server sees VERIFIER ip
   |══ TLS (prover holds keys) tunneled through verifier ══════════════════════════════▶|
   |   POST /graphql  Authorization: Bearer <token>  {viewer{login contributionsCollection…}}
   |◀═════════ JSON {data:{viewer:{login, …totalContributions:N}}} ═════════════════════|
   |── prove(): reveal server_id + request(minus token) + response; REDACT bearer ─────▶|
   |◀── Attestation (signed by notary key) ─────────────────|                          |
   |   store Attestation+Secrets on device → build Presentation on demand              |
```

**Taps / seconds (warm dev, iOS):** tap *Continue* → app-switch → Face ID → (1st-run consent) → back; token exchange + proxy proof. **2–3 taps, ~7–10 s** (notarize ~1–2 s of that; my local proxy run was **0.80 s** on loopback — see `00-tlsnotary.md`). **Cold** (not logged into GitHub): + one login sub-flow, +10–30 s. Returning users skip consent (Stage 1 §3) → **1–2 taps**.

**Mode = Proxy**, decided by constraint #3: `api.github.com` does not IP-flag cloud egress, so we keep proxy's speed and **browser-cleanliness** (the prover speaks WebSocket to the verifier; the verifier does the TCP — nothing extra to host; `00-tlsnotary.md` §"browser deployment"). Auto-fallback to **MPC** only if GitHub ever starts WAF-challenging the verifier IP.

---

## 2. The notarized request (exact)

```http
POST /graphql HTTP/1.1
Host: api.github.com
User-Agent: rep-prover/1.0
Authorization: Bearer gho_xxxxxxxxxxxxxxxxxxxx     ← REDACTED in the presentation
Accept: application/json
Content-Type: application/json
Content-Length: <n>
Connection: close

{"query":"query{ viewer{ login contributionsCollection(from:\"2026-01-01T00:00:00Z\"){ contributionCalendar{ totalContributions } } } }"}
```

Response (revealed):
```json
{"data":{"viewer":{"login":"octocat","contributionsCollection":{"contributionCalendar":{"totalContributions":1234}}}}}
```

**Reveal / redact map** (the heart of the proof):

| Transcript region | Action | Why |
|---|---|---|
| TLS server identity (`api.github.com` cert/SNI) | **reveal** | binds the claim to GitHub |
| Request line + `Host` + the GraphQL `query` body | **reveal** | the verifier must see *what was asked* to trust the answer |
| `Authorization: Bearer …` value | **REDACT** (reveal bytes before & after, omit the token) | never disclose the credential; same byte-range trick as `examples-zk/prover.rs:151` |
| Response `login` + `totalContributions` | **reveal** | the claim (identity + value) |
| any other response bytes | optional redact | minimize disclosure (v1 may reveal whole body — nothing sensitive) |

---

## 3. Proof / claim schema

The signed **Attestation** (from `crates/attestation`) commits to the server identity + a Merkle root over the transcript; the **Presentation** selectively opens the ranges above. REP wraps that into a portable claim:

```jsonc
// REP Verifiable Context Claim (VCC) — what lands in the graph
{
  "schema": "rep.vcc/1",
  "subject":   "rep:user:0x9af…",                 // REP user (DID/pubkey)
  "account":   { "platform": "github", "handle": "octocat" },  // from revealed viewer.login
  "predicate": "github.contributions.year",
  "value":     1234,
  "window":    { "from": "2026-01-01", "to": "2026-06-02" },
  "source":    { "server": "api.github.com", "endpoint": "POST /graphql",
                 "query_hash": "sha256:…" },        // hash of the revealed GraphQL query
  "evidence":  {
    "proto": "tlsnotary",
    "mode":  "proxy",
    "attestation": "<base64 TLSNotary attestation: signed Header{id,version,merkle_root}+Body>",
    "notary_key":  "ed25519:…",                     // trust anchor (attestation/lib.rs:19-21)
    "redactions":  ["request.authorization"]        // disclosed for auditability
  },
  "issued_at": "2026-06-02T17:00:00Z",
  "expires":   "2026-09-02T00:00:00Z"               // re-prove quarterly; contributions grow
}
```

A consumer trusts `value` iff it (a) trusts `notary_key`, (b) checks `source.server == api.github.com` in the attestation, and (c) recomputes `query_hash` to confirm the question matches the predicate's definition. No re-proving by the user.

---

## 4. How it slots into REP's Proof Graph Runtime / User Context Graph

The claim **mutates the graph** — this is the compounding moat:

```
 (rep:user:0x9af…) ──[owns, attested]──▶ (account:github/octocat)
                                              │
                                              ├─[attr]──▶ contributions.2026 = 1234   {notary_key, t, exp}
                                              └─[attr]──▶ (future) followers, repos, sponsorship…
```

- **Node created/merged:** `account:github/octocat`, linked to the REP user by an **`owns`** edge — provable because the claim came from a `viewer{}` query on the user's own token (token ⇒ ownership; `login` ⇒ which account).
- **Edge/attribute created:** `contributions.2026 = 1234`, stamped with the notary key, issuance time, and expiry.
- **Composition (the Runtime's job):** higher-order predicates are derived without new user friction — e.g. `is_active_developer := github.contributions.year ≥ 500`, or cross-source `dev_reputation := f(github.contributions, stackoverflow.reputation, leetcode.solved)`. Each new Stage-3 proof the user mints (Strava, Duolingo, SO…) attaches more attributes to the same subject, so the **next** app consuming "active developer" pays **zero** proving cost — the graph already holds an unexpired, notary-signed attribute. That reuse is the defensibility: friction is paid once, value is consumed many times.
- **Privacy/custody:** the bearer token and TLS keys never leave the device; the Attestation+Secrets are held client-side; only the minimal claim (login + count) is published. No server-side credential parking (anti-goal respected).

---

## 5. Runnable skeleton (proxy-mode proving call against the real endpoint)

Faithful to the shipped API in `crates/examples/proxy/proxy.rs` (commit `28614ef`); differences from the example are **(a)** real Mozilla/WebPKI roots instead of the fixture CA, **(b)** `api.github.com`, **(c)** a POST with a real bearer + GraphQL body, **(d)** redaction of the `Authorization` header.

```rust
use tlsn::{
    Session,
    config::{prove::ProveConfig, prover::ProverConfig, tls::TlsClientConfig,
             tls_commit::proxy::ProxyTlsConfig, verifier::VerifierConfig},
    connection::{DnsName, ServerName},
    verifier::{VerifierCommitStart, VerifierOutput},
    webpki::RootCertStore,
};
use http_body_util::Full;
use hyper::{Request, body::Bytes};
use hyper_util::rt::TokioIo;
use tokio_util::compat::{FuturesAsyncReadCompatExt, TokioAsyncReadCompatExt};

const HOST: &str = "api.github.com";
const GQL: &str = r#"{"query":"query{ viewer{ login contributionsCollection(from:\"2026-01-01T00:00:00Z\"){ contributionCalendar{ totalContributions } } } }"}"#;

// ── PROVER (REP app / WASM in browser) ───────────────────────────────
async fn prove(verifier_io: impl tokio::io::AsyncRead + tokio::io::AsyncWrite + Send + Unpin + 'static,
               bearer: &str, roots: RootCertStore) -> anyhow::Result<()> {
    let session = Session::new(verifier_io.compat());
    let (driver, mut handle) = session.split();
    let driver_task = tokio::spawn(driver);

    // Proxy mode: declare the server; the verifier will do the TCP.
    let prover = handle
        .new_prover(ProverConfig::builder().build()?)?
        .commit(ProxyTlsConfig::builder().server_name(DnsName::try_from(HOST)?).build()?)
        .await?;

    // No client socket here (unlike MPC) — verifier provides the transport.
    let (tls, prover) = prover.connect(
        TlsClientConfig::builder()
            .server_name(ServerName::Dns(HOST.try_into()?))
            .root_store(roots)               // real WebPKI/Mozilla roots
            .build()?,
    )?;
    let prover_task = tokio::spawn(prover.into_future());

    let (mut sender, conn) = hyper::client::conn::http1::handshake(TokioIo::new(tls.compat())).await?;
    tokio::spawn(conn);

    let auth = format!("Bearer {bearer}");
    let req = Request::builder()
        .method("POST").uri(format!("https://{HOST}/graphql"))
        .header("Host", HOST)
        .header("User-Agent", "rep-prover/1.0")
        .header("Authorization", &auth)        // ← will be redacted below
        .header("Accept", "application/json")
        .header("Content-Type", "application/json")
        .header("Connection", "close")
        .body(Full::<Bytes>::from(GQL))?;
    let resp = sender.send_request(req).await?;
    assert_eq!(resp.status(), 200);

    // Build the selective-disclosure proof.
    let mut prover = prover_task.await??;
    let mut b = ProveConfig::builder(prover.transcript());
    b.server_identity();                       // reveal api.github.com

    // Redact ONLY the bearer token bytes in the sent transcript.
    let sent = prover.transcript().sent();
    let needle = auth.as_bytes();
    let pos = sent.windows(needle.len()).position(|w| w == needle).expect("auth header present");
    b.reveal_sent(&(0..pos))?;                              // everything before token
    b.reveal_sent(&(pos + needle.len()..sent.len()))?;     // everything after token (incl. GraphQL query)

    // Reveal the whole response (login + totalContributions; nothing sensitive).
    b.reveal_recv(&(0..prover.transcript().received().len()))?;

    prover.prove(&b.build()?).await?;
    prover.close().await?;
    handle.close();
    driver_task.await??;
    Ok(())
}

// ── VERIFIER / NOTARY (REP backend) ──────────────────────────────────
async fn verify(prover_io: impl tokio::io::AsyncRead + tokio::io::AsyncWrite + Send + Sync + Unpin + 'static,
                roots: RootCertStore) -> anyhow::Result<(String /*login*/, u64 /*contributions*/)> {
    let session = Session::new(prover_io.compat());
    let (driver, mut handle) = session.split();
    let driver_task = tokio::spawn(driver);

    let v = handle.new_verifier(VerifierConfig::builder().root_store(roots).build()?)?;
    let v = match v.commit().await? {
        VerifierCommitStart::Proxy(v) => {
            // Verifier opens the TCP leg → server sees OUR ip (proxy-mode tradeoff).
            let sock = tokio::net::TcpStream::connect((HOST, 443)).await?;
            v.accept().await?.run(sock.compat()).await?
        }
        VerifierCommitStart::Mpc(v) => v.reject(Some("proxy expected")).await.map(|_| unreachable!())?,
    };
    let v = v.verify().await?;
    if !v.request().server_identity() { v.reject(Some("reveal server name")).await?; anyhow::bail!("no server id"); }
    let (VerifierOutput { server_name, transcript, .. }, v) = v.accept().await?;
    v.close().await?; handle.close(); driver_task.await??;

    // Policy checks → parse claim.
    let ServerName::Dns(name) = server_name.expect("server name");
    anyhow::ensure!(name.as_str() == HOST, "wrong server");
    let body = String::from_utf8(transcript.expect("t").received_unsafe().to_vec())?;
    let login = json_str(&body, "login");                 // small helpers
    let n     = json_u64(&body, "totalContributions");
    Ok((login, n))
    // → REP backend signs the Attestation and emits the VCC in §3.
}
```

**Browser/WASM variant (the shipping path):** compile the prover to WASM (`crates/wasm`); the prover's `verifier_io` is a **WebSocket** to the REP verifier. Because it's **proxy mode**, that's all — the verifier terminates the WebSocket *and* opens the TCP to `api.github.com` (no separate WS↔TCP relay to host; see `00-tlsnotary.md`). For a portable, offline-verifiable proof, run the verifier as a **Notary** (sign with `notary_key`, per `crates/examples/attestation/prove.rs`) so the user keeps `Attestation + Secrets` and produces a `Presentation` on demand; for an in-session check, the interactive verifier above is enough.

---

## 6. 30-day build checklist (hero only)
1. **GitHub OAuth app** (`read:user`), PKCE + app-switch (`ASWebAuthenticationSession` / Custom Tabs), token never leaves device.
2. **Verifier/notary service**: TLSNotary verifier accepting **proxy** sessions over WebSocket, allow-listing `api.github.com`; signing key for attestations.
3. **Prover** in the app/WASM: the §5 call; redact `Authorization`; reveal `login`+`totalContributions`+query.
4. **VCC + graph write** (§3–4): `owns` edge + `contributions.2026` attribute; expiry 90 d.
5. **Verify-and-fallback**: confirm `api.github.com` negotiates a TLSNotary-supported TLS suite (pin 1.2 if needed); wire an automatic **OAuth→cookie** and **proxy→MPC** fallback even though neither is expected for GitHub.
6. **Demo**: "Prove your 2026 GitHub contributions" → shareable badge backed by the attestation. Ship, measure real warm/cold taps+seconds, then add Duolingo (consumer virality) and Strava.
