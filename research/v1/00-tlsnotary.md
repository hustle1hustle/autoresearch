# Stage 0 — Grounding the Infra: TLSNotary Proxy vs MPC

**Method.** Every claim below is anchored to one of two primary sources: (a) the **actual TLSNotary source**, cloned at commit `28614ef` ("build: update Rust to version 1.96.0", #1158) into `/tmp/tlsn` — cited as `crates/...:line`; or (b) the **TLSNotary team's own blog/docs**, cited by URL. Where this brief's "verified facts" were wrong or imprecise, I say so under [Fact-check](#fact-check). Numbers come from the team's reproducible harness (`crates/harness`) and their May 2026 benchmark post, cross-checked against the harness config in the repo.

**Network reality of this research box** (affects what I could run): direct egress to `tlsnotary.org`, `github.com`, `crates.io` (website) returns **403**; but `git clone`, `raw.githubusercontent.com`, the cargo registry (`index.crates.io` / `static.crates.io`), and WebSearch all work. So I read the real code and built it locally (see [Local run](#local-run)); I could **not** load the browser demo (no browser + Cloudflare 403).

---

## 1. The three roles (from the code, not the blog)

TLSNotary is a protocol between **three parties**. The first two run the protocol; the third is the audience for the proof.

| Role | Code identity | What it does |
|---|---|---|
| **Prover** | MPC "Leader" — `MpcTlsLeader` (`crates/mpc-tls/src/lib.rs:19`) | The user's device/app/browser. Builds the HTTP request, (co-)holds the TLS keys, and performs **selective disclosure** of the transcript. |
| **Verifier / Notary** | MPC "Follower" — `MpcTlsFollower` (`crates/mpc-tls/src/lib.rs:18`) | Witnesses the TLS session. A **Verifier** checks claims live (interactive); a **Notary** additionally *signs* an `Attestation` so a third party can verify later, offline. |
| **Attestation Verifier** | `crates/attestation/src/presentation.rs` | Whoever later consumes the proof. Trusts the data **iff it trusts the Notary's verifying key** (`crates/attestation/src/lib.rs:19-21`). |

The session keys are the crux of the security model. `SessionKeys` (`crates/mpc-tls/src/lib.rs:42-54`) carries `client_write_key`, `client_write_iv`, `server_write_key`, `server_write_iv`, `server_write_mac_key`. **In MPC mode these are secret-shared between Leader and Follower** — neither holds them in the clear. **In proxy mode the prover alone holds them.** That single difference drives everything else.

### What the proof actually asserts
From `crates/attestation/src/lib.rs:26-39`: an **Attestation** is a signed document = **Header** (signed: unique id, protocol version, **Merkle root** of the body) + **Body** (fields: the **server identity** and **commitments to the transcript**). The prover is committed to the `ServerName` and the application-data `Transcript` (`:9-13`). The connection commitment also fixes the **TLS version** (1.2/1.3) and **server DNS name** (`crates/core/src/connection.rs:14-38`). Later the prover builds a **Presentation** that selectively reveals byte-ranges (`commit_sent`/`commit_recv`, `reveal_sent`/`reveal_recv`). This is the schema Stage 4 builds on.

---

## 2. Proxy mode — trust model in my own words (from `crates/examples/proxy/proxy.rs`)

**Mechanic.** The prover configures `ProxyTlsConfig` and *does not* open a socket to the server. Instead the **verifier opens the TCP connection to the server** and relays bytes:

```
crates/examples/proxy/proxy.rs:208-217   (verifier side)
  VerifierCommitStart::Proxy(verifier) => {
      let client_socket = tokio::net::TcpStream::connect(server_addr).await.unwrap();
      verifier.accept().await?.run(client_socket.compat()).await?
  }
```

The prover tunnels a normal TLS client session *through* that relay (`proxy.rs:92-105`, "connect TLS through the proxy instead of directly to the server via TCP. The verifier will forward traffic to the actual server"). **The prover terminates TLS and holds the keys; the verifier sees only ciphertext.** After the session the prover produces a ZK proof that the revealed plaintext is consistent with the ciphertext the verifier witnessed, under keys consistent with the recorded TLS transcript.

**Security assumption (network topology).** Because the prover holds all the keys, the *only* thing stopping a malicious prover from revealing forged "server" data is that **the verifier itself opened the connection to the genuine server by name and relayed exactly those bytes**. So proxy mode rests on a network-topology assumption: *the verifier has a direct, honest path to the real server, and the prover cannot interpose between verifier and server.* If that holds, the witnessed ciphertext is authentic; the prover can only decrypt/redact, not fabricate. (Confirmed in the team's framing: "assumes the Verifier has a direct connection to the Server, and that a malicious Prover cannot bypass or otherwise insert themselves in-between the Verifier and Server." — [proxy-mode post](https://tlsnotary.org/blog/2026/04/22/proxy-mode/).)

**IP consequence (the crux of this whole task).** The packet to the server originates from the **verifier's** socket (`proxy.rs:215`). So **the server sees the verifier's IP, not the user's.** If the verifier runs in a datacenter, IP-reputation/bot defense may flag or block it. The verifier *does* learn the server name in proxy mode (it must, to `connect`) — note `.server_name(...)` is required on the prover's `ProxyTlsConfig` (`proxy.rs:86-88`), unlike MPC where the verifier need not learn the target during the online phase.

**Privacy.** Still preserved against the verifier: only encrypted records cross the prover↔verifier link; the prover is the only holder of the symmetric keys.

---

## 3. MPC mode — trust model in my own words (from `crates/examples/basic/basic.rs`)

**Mechanic.** Prover and verifier jointly compute the TLS handshake and record layer over 2PC/MPC, so the keys are split (`SessionKeys`, above). Crucially, **the prover's device opens the TCP socket to the server**:

```
crates/examples/basic/basic.rs:100-101   (prover side)
  // Open a TCP connection to the server.
  let client_socket = tokio::net::TcpStream::connect(server_addr).await?;
```

The verifier (`basic.rs:184` `verifier(socket)`) is handed **only the prover socket** — it never connects to the server; it runs the MPC (`verifier.accept().await?.run().await?`, `:223`). So the verifier does not learn the target server during the online phase, and the request leaves from the **user's own residential/mobile IP**.

**Security guarantee.** Because the MAC/authentication of TLS records is computed jointly and neither party holds full keys, **even a malicious prover cannot forge server responses** — no network-topology assumption needed. This is the strongest guarantee.

**Cost (why it's slow).** MPC must **preprocess garbled-circuit material before the handshake**. The prover declares limits up front — `MpcTlsConfig::max_sent_data` / `max_recv_data` (`basic.rs:89-96`: "must configure the amount of data we expect to exchange beforehand, which will be preprocessed prior to the connection. Reducing these limits will improve performance"). Two optimizations live in `crates/mpc-tls/src/config.rs`:
- **`defer_decryption` (default `true`, `:43`,`:84`):** received data is decrypted *locally, without MPC, after the connection closes* → "improving bandwidth usage and performance." This is why **response size barely affects MPC cost** — only the *online* portion (`max_recv_online`) is expensive.
- **`low_bandwidth()` (`:76-79`):** sets the PRF to `NetworkMode::Reduced`, trading rounds for bytes on slow uplinks.

The per-record overhead scales: the comment at `config.rs:24-30` notes `max_data=32KB → ~15 records → ~3MB upload from prover to verifier`; the full handshake preprocessing is the ~30 MB the blog cites.

---

## 4. Mode negotiation — the "toggle" is the prover's choice, the verifier's veto

The prover picks the mode by which TLS-commit config it builds (`ProxyTlsConfig` vs `MpcTlsConfig`). The verifier inspects the request and decides:

```
crates/examples/proxy/proxy.rs:206-218  — accepts BOTH Mpc and Proxy
crates/examples/basic/basic.rs:207-229  — accepts Mpc, REJECTS Proxy ("expecting to use MPC-TLS")
```

`VerifierCommitStart::{Mpc, Proxy}` (`crates/tlsn/src/verifier/...`) is the branch point. So an operator's verifier/notary **policy** decides which modes (and, in MPC, which `max_*` sizes — `basic.rs:210-221` rejects oversized requests as DoS protection) it will service. There is no third "mode"; it is a binary chosen per-session.

---

## 5. Local run — building & timing the two modes myself {#local-run}

I built the real examples against the bundled `tlsn-server-fixture` (TLS server with a self-signed cert; supports an `Authorization: Bearer` check at `crates/server-fixture/server/src/lib.rs:180-184` — this is the workshop's `--authenticated` path). Build + run status is recorded in this file's companion run log; the headline:

- **What's identical across modes:** the HTTP request and the redaction logic are byte-for-byte the same in `proxy.rs` and `basic.rs` (lines 118-159 in both). The *only* code differences are the config type and **who calls `TcpStream::connect`** (prover in MPC, verifier in proxy). That is the entire architectural delta — verified by diffing the two example files.
- **Measured timing:** see the [run log](#run-log) appended below. Where the local build is unavailable, I defer to the team's harness numbers (§6), which are statistically sounder than a single local run anyway.

> Note on rigor: the bundled benchmarks run on an emulated virtual network (`crates/harness/runner/src/network.rs` uses `tc` to set egress `bandwidth`+`delay`), sweeping the exact profiles in `bench.toml`. A single localhost run (sub-ms RTT, no bandwidth cap) would *understate* MPC's real-world penalty, because MPC's cost is dominated by uplink bandwidth × latency, both ≈0 on loopback. So I treat §6 as the authoritative timing.

---

## 6. Timing — the numbers, with their network context {#timing}

Benchmark conditions from the repo (`crates/harness/bench.toml`): payload **1 KB request / 2 KB response**; profiles **Cable 20 Mbps↑/20 ms**, **Mobile-5G 30 Mbps↑/30 ms**, **Fiber 100 Mbps↑/15 ms**. Headline: *"TLSNotary is primarily bottlenecked by upload bandwidth"* (`bench.toml:11-12`) — true because of MPC's GC upload; proxy has none.

From the [May 10 benchmark post](https://tlsnotary.org/blog/2026/05/10/blog-proxy-mode/) (cross-checked against the August 2025 baseline post):

| Axis | MPC | Proxy | Notes |
|---|---|---|---|
| **Full-reveal, 1 KB→51 KB** | **~14.5 s** (flat) | **~1.6 s** (flat) | 50× response-size change → only a few % runtime change. Response size ≈ free (defer-decryption). |
| **Preprocess floor** | **~13 s** (uploads ~30 MB GC material) | **none** | This floor *is* MPC's cost. |
| **Upload sweep 5 Mbps → 1 Gbps** | 30 MB upload: **~52 s @ 5 Mbps → ~1 s @ 1 Gbps** | **~4 s → ~1 s** | |
| **Speedup ratio (Proxy advantage)** | — | **12.5× @ 5 Mbps → 1.8× @ 1 Gbps** | Largest where users live (residential 5–50 Mbps); shrinks on fiber. |
| **Latency sweep** | slope ~2× proxy's (~40 comm rounds) | fewer rounds | @200 ms RTT: **MPC 13.3 s vs Proxy 6.2 s (2×)**; @10 ms ≈ 4.2×. |

**Takeaway:** the brief's "Proxy ~1–2 s" and "MPC ~3–15 s" are correct for typical conditions. The honest framing: **MPC ≈ 13–15 s on real residential/mobile links, dominated by a fixed preprocessing floor; Proxy ≈ 1–2 s, ~flat in payload.** A newer post, [The full-reveal fast path (May 19)](https://tlsnotary.org/blog/2026/05/19/fast-reveal/), pushes the "response size stops mattering" point further (full-reveal cheaper than selective reveal past a threshold) — relevant when we want to attest large JSON bodies.

---

## 7. Fact-check of the brief's "verified facts" {#fact-check}

| Brief's claim | Verdict | Evidence |
|---|---|---|
| Proxy mode = verifier connects to server & forwards encrypted TLS; ZK verified after | ✅ Confirmed | `proxy.rs:215` (verifier `TcpStream::connect`), `proxy/README.md:3` |
| Proxy ~1–2 s for 1–2 KB | ✅ Confirmed | ~1.6 s full-reveal; ~1 s @ fiber ([May 10 post]) |
| MPC ~3–15 s; heaviest is prover↔verifier bandwidth (GC + OT, multi-round) | ✅ Confirmed | ~13 s preprocess floor, ~30 MB upload, ~40 rounds ([May 10 post]); `config.rs` preprocessing |
| MPC: no party holds full keys; request from user's residential/mobile IP | ✅ Confirmed | `SessionKeys` split (`mpc-tls/lib.rs:42-54`); prover connects (`basic.rs:101`) |
| MPC: verifier doesn't learn the server during online phase | ✅ Confirmed | verifier has no server socket in MPC (`basic.rs:184,223`) |
| Proxy: server sees verifier's IP (datacenter → flag/block; residential proxy weakens trust) | ✅ Confirmed | `proxy.rs:215`; topology assumption in [proxy-mode post] |
| Browser MPC needs a WS↔TCP proxy; proxy mode is "browser-clean" | ✅ Confirmed | harness README:65 ("Chrome connects to WebSocket proxies"); WS proxy is a transport relay only — in proxy mode the browser speaks WebSocket to the verifier and **the verifier does the TCP**, so no separate relay to host ([proxy-mode post]) |
| Two modes, toggleable | ✅ Confirmed | `VerifierCommitStart::{Mpc,Proxy}`; prover picks config, verifier accepts/rejects |
| Notary supports JWT bearer auth | ✅ Confirmed | optional `Authorization: Bearer <JWT>` to notary server ([notary_server docs](https://tlsnotary.org/docs/notary_server/)); **not in this monorepo** — it's the separate notary-server |
| Prover can present X.509 client certs | ✅ Confirmed | `attestation/prove.rs:118` (`CLIENT_CERT_DER`); `sdk-core/config.rs:287` "Client certificates (DER or PEM)" |
| Low-bandwidth "latency" network setting for MPC | ⚠️ Corrected | The real knob is `low_bandwidth()` → `NetworkMode::Reduced` (`config.rs:76-79`). "Latency" is a *harness emulation* parameter (`tc` delay), **not** a protocol mode. |
| PSE's hosted proxy only allows whitelisted domains → self-host for arbitrary targets | ✅ Confirmed | PSE's public **websockify** WS proxy whitelists domains; notary server can restrict allowed domains too → self-host for arbitrary targets ([notary_server docs]) |
| `demo.tlsnotary.org` `--authenticated` appends an auth token to reach "private" data | ✅ Confirmed | DefCon 2025 workshop; mirrored by the fixture's Bearer check (`server-fixture/server/src/lib.rs:180-184`) |
| Reclaim: residential proxies, ~2–4 s mobile, "JSON stable / HTML fragile" | → Stage 2 | cross-referenced in `02-targets.md` |

---

## 8. Mode-selection decision table (keyed on the three binding constraints) {#decision-table}

The deciding constraint is almost always **#3, bot/network defense on the data endpoint**, via the verifier-IP question.

| If the data endpoint… | …pick | Why (constraint) |
|---|---|---|
| is an **open JSON API on a dedicated API host** that tolerates datacenter/cloud clients (`api.spotify.com`, `api.github.com`, `api.strava.com`, public REST/GraphQL) | **Proxy** | #3 favorable: API hosts don't IP-flag cloud egress; get the ~1–2 s, browser-clean win |
| sits behind **aggressive bot defense / IP-reputation / device attestation** (consumer web of Amazon, Uber, social, many bank webapps; Cloudflare/Akamai/PerimeterX challenge pages) | **MPC** | #3 hostile to a datacenter verifier-IP → use the user's real residential/mobile IP; survives IP blocking |
| demands the **strongest trust** (high-stakes, adversarial prover, no trustworthy network path) | **MPC** | cryptographic authenticity even vs malicious prover; no topology assumption |
| is **browser-only and we want zero extra infra** | **Proxy** | verifier terminates WebSocket *and* does TCP → no WS↔TCP relay to host |
| is fetched by a **low-bandwidth mobile user**, low stakes, possibly large response | **Proxy** | avoids the 30 MB GC upload that dominates MPC on a phone uplink (12.5× gap @5 Mbps) |
| is **geo/IP-restricted to the user** but reachable from their device, not our verifier | **MPC** | the user's device makes the connection |

**Residential-egress nuance (open-question #1 preview).** You *can* make proxy mode look like a residential client by routing the verifier through a residential proxy — but that (a) re-introduces a third party in the network path who could in principle interpose, **weakening proxy mode's one security assumption**, and (b) re-introduces a vendor dependency we explicitly want to avoid. So the honest hierarchy for a flagged target is: **MPC (user-IP, no extra trust) > proxy-via-residential (fast, weaker trust, vendor) > datacenter-proxy (will be blocked).** Where exactly each Tier-2 target falls is quantified in `02-targets.md`.

---

## Run log {#run-log}

**I built and ran both modes locally** against the bundled `tlsn-server-fixture` (commit `28614ef`). Toolchain note: the workspace needs **rustc ≥ 1.95** (`mpz-fields` requires it); the box's default 1.94.1 built the fixture but not the examples, so I installed **1.96.0** and rebuilt (`cargo +1.96.0 build --release -p tlsn-examples --example proxy --example basic`, exit 0).

Wall-clock, 3 runs each, `time ./target/release/examples/<ex>` with `SERVER_PORT=4000`:

| Mode | Run 1 | Run 2 | Run 3 | Median |
|---|---|---|---|---|
| **Proxy** (`examples/proxy`) | 0.803 s | 0.805 s | 0.795 s | **0.80 s** |
| **MPC** (`examples/basic`) | 1.242 s | 1.300 s | 1.296 s | **1.30 s** |

Both verified successfully (the verifier's `find("Herman Melville")` / server-name checks passed; the `Secret` header was redacted from the presentation). **Proxy was ~1.6× faster than MPC even here.**

**Read this number correctly — it is a floor, not a real-world figure.** The run is on **loopback** (sub-ms RTT, no bandwidth cap) with the example's tiny limits (`MAX_SENT_DATA = 4 KB`, `MAX_RECV_DATA = 16 KB`, `basic.rs:31-34`). That setup **hides MPC's dominant cost**: there is no uplink bottleneck for the garbled-circuit upload and the GC material is small at 4 KB/16 KB. So loopback shows only the residual compute gap (~1.6×). On a real residential uplink the GC upload dominates and the gap blows out to the **12.5× @ 5 Mbps** the team measures (§6). **Conclusion: my local run confirms the *architecture and direction* (proxy is faster, both work, redaction works); the *magnitude* of MPC's real-world penalty must be taken from the team's network-emulated harness (§6), which my loopback run structurally understates.**
