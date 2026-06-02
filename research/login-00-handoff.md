# Stage 0 — The login → proving contract (proxy mode)

*What must login hand the prover so TLSNotary can run? Reused from the v1 code-read of `tlsnotary/tlsn` @ `28614ef` (see `research/v1/00-tlsnotary.md`, `…/04-hero-flow.md`); restated here as a pure login-compatibility constraint. No proof-selection — only "what credential the login must yield."*

## The mechanic (why the contract is what it is)
In **proxy mode** the **prover holds the TLS session keys** and makes a **fresh HTTPS request** to the target *through* the verifier (the verifier opens the TCP and relays ciphertext — `crates/examples/proxy/proxy.rs:215`). The prover then **selectively reveals** response bytes and **redacts the credential**. So login's *only* job is to put a **replayable credential on that one fresh request**. The credential is used **once, client-side, then redacted from the proof** — never revealed, never parked server-side.

**The `--authenticated` path is nothing special:** the workshop's auth token is just an HTTP header the prover sets on the request. In the code, the prover does `.header(AUTHORIZATION, "Bearer <token>")` (`crates/examples-zk/prover.rs:123`) and then **"reveal the entire HTTP request except for the authorization bearer token"** (`…/prover.rs:151`); the fixture simply checks `Authorization: Bearer …` (`crates/server-fixture/server/src/lib.rs:180-184`). "Authenticated" = *the request carries the credential, and the credential's byte-range is excluded from disclosure.* That's the whole thing.

## The contract (concrete)
**To notarize, login must hand the prover ONE of:**

| # | Credential shape | How the prover uses it | Redaction |
|---|---|---|---|
| **(a)** | **Bearer token** (OAuth/OIDC access token for the *target's* API) | sets `Authorization: Bearer <t>` on the fresh request | redact one header range — cleanest |
| **(b)** | **Session cookie jar** for the *target* site | sets `Cookie: <session>` on the fresh request to the data endpoint | redact the `Cookie` header; `HttpOnly` is fine (browser auto-sends it / extension captures via `webRequest`) |
| **(c)** | **A live authenticated session in a browser surface the prover controls** (system-browser session or extension context) | reuses that surface's cookies for the fresh request (this is just how (b) is obtained warm) | same as (b) |

**It does NOT need:** the WebAuthn assertion itself, a refresh token, or any server-side session. Just the access credential for **one** request.

## Which login methods satisfy it (this bounds Stage 1)

| Login method | Yields a *target* credential? | Contract fit |
|---|---|---|
| **App-switch OAuth (PKCE)** | ✅ target **bearer** | **✓✓ best** — redact one header. *Blocked only if the token is DPoP/mTLS sender-constrained (rare in consumer; RFC 9449) — then not freely replayable.* |
| **System-browser cookie reuse** (`ASWebAuthenticationSession`/Custom Tabs) | ✅ target **cookie jar** (warm) | **✓✓ the warm path** — satisfies (b)/(c). The single biggest lever. |
| **Passkey same-device** | ✅ target **cookie** *only if the passkey's RP is the target* | **✓ if RP==target**, else ✗ (a passkey into *our* app yields no target credential) |
| **SMS OTP / email code** | ✅ target **cookie** (post-code) | **✓** but typed → fallback |
| **OAuth device grant (RFC 8628)** | ✅ target **bearer** | ✓ but built for input-constrained devices; slower than app-switch on a phone |
| **Sign in with Apple / Google** | ⚠️ `id_token`/token scoped to **Apple/Google** | **✗ for a 3rd-party target** (identity to *our* RP, not a credential for service X) — ✓ only if the target *is* Google/Apple |
| **Magic link (email)** | ⚠️ cookie, but possibly in the **wrong browser context** | ⚠️ session-split risk → prefer OTP |
| **QR cross-device** | ⚠️ session on the **other screen** | ⚠️ prover must run there + token-exfiltration anti-goal |
| **Manual password** | ✅ target session | ✓ mechanically — **anti-goal** (no typed-credential happy path) |

## The decisive line for the router
The methods that satisfy the contract with a **target** credential **and zero typing** are exactly three: **warm system-browser cookie reuse, app-switch OAuth, and passkey-if-the-RP-is-the-target.** Everything else (OTP, magic link, QR, password) is a fallback that either requires typing, a second device, or risks landing the session outside the prover's context. **Sign-in-with-Apple/Google is a trap here** — it's a gorgeous one-tap that usually yields *no usable target credential*, so it belongs only when the target itself is Google/Apple. Stage 1 ranks the friction; Stage 3 routes among the contract-satisfying three.
