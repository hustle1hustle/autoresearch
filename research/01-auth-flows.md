# Stage 1 — Auth-Flow Matrix for REP (zkTLS / TLSNotary onboarding)

**Author:** Research agent · **Date:** June 2026
**Scope:** For each auth mechanism, quantify taps / seconds (warm vs cold) / iOS vs Android, the credential it yields, and whether that credential can drive a *fresh, notarizable* HTTPS request through TLSNotary **proxy mode**.

---

## 0. How TLSNotary proxy mode constrains the answer (read first)

TLSNotary proxy mode (shipped April 2026) works as follows: the **prover** (user's device / browser / app) performs a **standard TLS handshake through the verifier**, which forwards the encrypted packets in both directions but **cannot decrypt them**; the prover captures the session secrets and later proves in zero-knowledge that the traffic the verifier observed is a legitimate TLS session, then **selectively discloses** chosen byte ranges (reveal the fact, redact the auth header). "As the prover holds the full TLS session keys… [breaking that] completely breaks the integrity of the protocol." ([TLSNotary proxy-mode blog, 2026-04-22](https://tlsnotary.org/blog/2026/04/22/proxy-mode/); [proxy-mode benchmarks, 2026-05-10](https://tlsnotary.org/blog/2026/05/10/blog-proxy-mode/))

**Decisive consequence:** the auth step must hand the prover a **replayable credential that authorizes a *new* request** to the data endpoint we want to notarize. Two shapes work:
- **(a) Bearer token** — `Authorization: Bearer <token>` from an OAuth/OIDC access token. Replayable from any new TLS session *unless* the token is sender-constrained (DPoP/mTLS — see §2).
- **(b) Session cookie** — replayed on the data endpoint. The TLSNotary browser extension captures headers (incl. `HttpOnly` cookies the page JS can't read) via Chrome's `webRequest` API, and **commits sensitive headers with a Pedersen commitment / redacts them rather than REVEAL**ing. ([TLSNotary extension docs](https://tlsnotary.org/docs/extension/); [build write-up](https://www.lucianolupo.com/posts/tlsnotary-zk-proofs))

The auth header/cookie is then excluded from the revealed byte ranges. The mechanism's job is purely to *produce credential (a) or (b) as fast as possible.*

Latency budget context (proxy mode, the mode we'd ship for UX): at **10 ms RTT proxy ≈ 4.2× faster than MPC-TLS**; at 200 ms RTT, proxy = **6.2 s** vs MPC 13.3 s. MPC-TLS carries a ~13 s preprocessing floor (uploads ~30 MB garbled circuits before the handshake) — unacceptable for "onboarding wow," so proxy mode is assumed throughout. ([benchmarks 2026-05-10](https://tlsnotary.org/blog/2026/05/10/blog-proxy-mode/))

> Note: proxy mode (and TLSNotary generally) has historically been pinned to **TLS 1.2 / `TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256`**. Targets that are TLS-1.3-only need verification that the shipped prover supports them — flagged in §4.

---

## 1. Corrected, sourced matrix

Times are **end-to-end auth only** (tap "Continue" → credential in hand), *excluding* the TLSNotary notarization itself. "Warm" = already logged into the target service on the device; "Cold" = must do the one-time login sub-flow first. Numbers marked **EST** are my estimates triangulated from the cited mechanism behavior; numbers with a URL are sourced.

| Method | Taps (warm) | Seconds warm / cold | iOS specifics | Android specifics | Credential yielded | Main funnel-breaker |
|---|---|---|---|---|---|---|
| **Passkey same device** (Face/Touch ID, conditional UI) | 1–2 | **~3–8.5 s** warm / +30–60 s cold (create passkey) | `ASAuthorizationController` + Face ID; autofill via conditional UI | Credential Manager + biometric; conditional UI on Chrome | **App session cookie / OIDC code→token** at *your* RP — NOT a token for the third-party data API | Needs RP to support passkeys; auth is to *you*, not the target platform |
| **Sign in with Apple / Google** (OIDC) | 2 | **1.4 s** (Google One Tap median) / 3–8 s cold | One Tap / SiwA sheet, Face ID | One Tap sheet, biometric | **OIDC `id_token` + access token** scoped to Apple/Google APIs | Target service must offer it; *the fact must be in Apple/Google's scope* (rarely is) |
| **App-switch OAuth + PKCE** (target app installed & logged in) | **1–2 warm-repeat / 2–3 first-consent** | **~5–10 s** warm / +login sub-flow if cold | App-switch via universal link; biometric in target app | App-switch via App Link / intent; biometric | **OAuth access token (Bearer)** for the target platform's API | Consent screen drop-off **(first time only — returning users skip consent)**; **fact may not be in any scope** |
| **System browser + cookie reuse** (`ASWebAuthenticationSession` / Chrome Custom Tabs) | **2–3** (iOS adds the consent sheet) | **~5–12 s** warm / +login if cold | **Mandatory "…wants to use *site* to Sign In" sheet** to reuse Safari cookies | **No prompt**; CCT shares Chrome's cookie jar silently | **Web session cookie** for the target site | iOS scary system sheet (can't be removed without losing cookie reuse) |
| **FIDO CDA** (phone→desktop, QR + BLE hybrid) | 2–3 | **~10–20 s** EST warm / +passkey setup cold | Scan QR in Camera, Face ID; BLE proximity | Scan QR, biometric; BLE proximity | **App session / OIDC at your RP on the *desktop*** | Needs 2nd device + Bluetooth on + a passkey; internet tunnel required |
| **SMS OTP** | 3–5 | **~15–40 s** | iOS Security Code AutoFill (QuickType suggests code ~3 min) | SMS Retriever / User Consent API (auto-read, no SMS permission) | **Web/app session** at the service (post-OTP) | Delivery latency + entry; carrier failures |
| **QR cross-device** (phone app scans QR on another screen, WhatsApp/Telegram-Web style) | **3–5** (find Linked Devices → scan) | **~10 s** (Telegram "under ten seconds"; WhatsApp scan 2–3 s + sync) | Scanner buried in app's Linked-Devices menu | Same | **Web session for the *other* screen** (the scanning phone authorizes a desktop/web session) | Two screens required; scanner buried; **does NOT give the phone a fresh credential** |
| **Email OTP (code)** | 4–6 | **~30–45 s** EST | Code visible in notification → faster than link | Same | **Web/app session** post-code | Leaves app to inbox; ~**14 s slower than no-switch**, but faster than magic link |
| **Magic link** (email) | 4–6 | **~45–60 s** EST | Forces tab/app switch; may open new browser context (session split risk) | Same | Session in *whatever context the link opens* (may not be the prover context) | Tab switch costs **~14 s vs Email OTP** ([Clerk study]); link can land in wrong browser |
| **Manual password (no keychain)** | 10+ | **30–90 s** | — | — | Web/app session | Forgotten password; **violates our anti-goal (no manual password happy-path)** |

### Sources for the matrix numbers
- Passkey login **8.5 s** vs **31.2 s** MFA (73% faster); Microsoft synced passkeys **~3 s vs 69 s**: [FIDO Passkey Index 2025](https://fidoalliance.org/passkey-index-2025/) ([PDF](https://fidoalliance.org/wp-content/uploads/2025/10/FIDO-Passkey-Index-October-2025.pdf)).
- Conditional UI = passkey appears in the username autofill chip (1 tap to pick + biometric): [Corbado, WebAuthn Conditional UI](https://www.corbado.com/blog/webauthn-conditional-ui-passkeys-autofill).
- **Google One Tap median 1.4 s** (vs 6.3 s password+TOTP): [Security Boulevard, One Tap guide](https://securityboulevard.com/2025/09/the-complete-guide-to-google-one-tap-login-everything-developers-need-to-know/).
- App-switch OAuth must use external user-agent + PKCE; iOS `ASWebAuthenticationSession`, Android Custom Tabs: [RFC 8252](https://www.rfc-editor.org/rfc/rfc8252.html); [RFC 7636 PKCE](https://datatracker.ietf.org/doc/html/rfc7636).
- **Returning OAuth users skip the consent screen by design**: [Google Workspace OAuth consent docs](https://developers.google.com/workspace/guides/configure-oauth-consent); [Supabase discussion #3712](https://github.com/orgs/supabase/discussions/3712).
- iOS cookie-reuse **requires** the consent sheet; `prefersEphemeralWebBrowserSession=true` removes the sheet **but kills cookie sharing**: [Apple `prefersEphemeralWebBrowserSession`](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/prefersephemeralwebbrowsersession); [Okta, History of Mobile SSO](https://developer.okta.com/blog/2022/01/13/mobile-sso).
- Android **Chrome Custom Tabs share the cookie jar with Chrome** (no equivalent prompt): [Android CustomTabsSession](https://developer.android.com/reference/androidx/browser/customtabs/CustomTabsSession); [Steamclock, CCT login issues](https://steamclock.com/blog/2025/05/android-chrome-custom-tabs/).
- FIDO CDA = QR + BLE proximity + cloud CTAP2 tunnel ("hybrid", CTAP 2.2): [Corbado CDA](https://www.corbado.com/glossary/cda); [Corbado hybrid transport](https://www.corbado.com/blog/webauthn-passkey-qr-code).
- SMS: iOS Security Code AutoFill (QuickType, ~3 min window, message must contain "code"): [The SMS Works, OTP formatting](https://thesmsworks.co.uk/blog/sms-otp-formatting/). Android SMS Retriever / User Consent API auto-read without SMS permission: [Android autofill docs](https://developer.android.com/identity/autofill/autofill-services).
- QR cross-device login mechanics & timing ("under ten seconds"; WhatsApp 2–3 s scan + sync): [Telegram qr-login API](https://core.telegram.org/api/qr-login); [WhatsApp Web QR process](https://medium.com/@anisettyanudeep/demystifying-the-whatsapp-web-desktop-qr-code-scanning-process-9e5a0ba10c22).
- **Email OTP ~14 s faster than magic link** (tab-switch cost; OTP visible in notification): [Clerk study via Scalekit](https://www.scalekit.com/blog/otp-vs-magic-links-passwordless-authentication); [ProductAgency, magic links critique](https://www.productagency.com.au/insights/dont-use-magic-links-for-sign-in).

**Corrections to the starting hypothesis matrix:**
1. **Sign in with Apple/Google is faster than the hypothesis said** — Google One Tap warm median is **1.4 s**, not 3–8 s. Keep 3–8 s only for the *cold* (first-consent) case.
2. **App-switch OAuth taps drop to 1–2 for returning users** — the consent screen only appears on first authorization; after that it's auto-approved. The "2–3 / consent drop-off" applies to *first run only*.
3. **The two cookie-based remote flows are not equivalent.** "System browser + cookie reuse" (single device, in-app sheet) is genuinely 2–3 taps. **"QR cross-device" is a *different device* flow** and—critically for us—authorizes a session on the *other* screen, not on the scanning phone (see §3 funnel note). The hypothesis conflated the friction but the architectures differ.
4. **Magic link belongs *below* Email OTP**, not above — the tab switch makes it slower and risks landing the session in a different browser context than the prover. (Hypothesis had them adjacent; the ordering matters.)

---

## 2. Per-mechanism TLSNotary-compatibility notes

| Mechanism | Credential it produces | Drives a notarizable request? | Blockers / caveats |
|---|---|---|---|
| **App-switch OAuth + PKCE** | **Bearer access token** for the target API | **Yes — cleanest case.** Prover opens a fresh TLS session to the API with `Authorization: Bearer …`, notarizes the response, redacts the header. | **(i) Fact must be in an OAuth scope** — see §the Spotify finding below. **(ii) DPoP/mTLS-bound tokens are NOT freely replayable** (§2a). **(iii) Short token TTL** (15–60 min) is fine — we notarize immediately. Refresh-token *rotation* is irrelevant if we use the access token once. ([token TTL guidance](https://auth0.com/blog/refresh-tokens-what-are-they-and-when-to-use-them/)) |
| **Sign in with Apple/Google (OIDC)** | `id_token` (identity) + access token scoped to **Apple/Google** APIs | Only if the *fact lives in Apple/Google's API* (e.g. "verified email"). For third-party facts it just identifies the user to *our* RP — not directly notarizable against the target. | The `id_token` proves identity to us, not a fact on platform X. Usually a **login primitive, not a data credential.** |
| **System browser + cookie reuse** | **Web session cookie** for the target site | **Yes, via the cookie path.** Prover replays the cookie on the data endpoint inside a new TLS session; cookie redacted via Pedersen commitment. This is the path for **facts with no public API**. | **`HttpOnly` cookies** can't be read by page JS but **are auto-sent by the browser** on same-origin requests, and the **extension captures them via `webRequest`** — so they ARE usable. ([MDN HttpOnly](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Cookies); [TLSNotary extension](https://tlsnotary.org/docs/extension/)) Risks: cookie may be bound to a User-Agent / device fingerprint; some sites rotate session cookies; CSRF tokens may be needed on POSTs. |
| **Passkey same device** | Session/cookie or OIDC code→token **at the RP that owns the passkey** | Yes **only if the passkey RP is the target platform** (i.e., the target itself supports passkeys and we capture *its* session). Otherwise it authenticates the user to *us*. | Passkey assertion itself is single-use and **not replayable** — what we replay is the **session it bootstraps**, not the WebAuthn assertion. |
| **FIDO CDA (phone→desktop)** | Session/token **on the desktop** RP | Same as same-device passkey but the credential lands on the **desktop** browser — prover/notarization must run there, not on the phone. | Adds 2nd device + BLE + cloud tunnel; only worth it for desktop-originated flows. |
| **QR cross-device login** | **Web session for the screen showing the QR** (e.g., a desktop) | Yes — but the session is created **where the QR was displayed**, not on the scanning phone. So the prover/notarization environment must be that screen. | **Anti-goal hazard:** harvesting the session token minted at the QR endpoint and shipping it server-side = silent token exfiltration. Consent must be explicit and the token scoped to the proof (see §4). |
| **SMS OTP / Email OTP / Magic link** | **Web/app session** at the target after code/link | Yes — yields a session cookie (cookie path) and possibly a token. Same replay mechanics as cookie reuse. | Magic link may open a **different browser context** than the prover → session not visible to the notarizing client. Prefer **OTP code** so the session is minted in the prover context. |
| **Manual password** | Web/app session | Yes mechanically | **Disallowed by anti-goal** (no manual-password happy path). |

### 2a. The token-binding blocker (DPoP / mTLS) — severity assessment
A bearer token is replayable from TLSNotary's new TLS session **only if it is a plain bearer token**. Sender-constrained tokens break this:
- **DPoP (RFC 9449):** every resource request needs a fresh proof-JWT signed by the client's private key, validated *independent of the transport connection*. If the target API requires DPoP, the prover would have to perform the DPoP signing inside the notarized request — possible but adds complexity, and the bound key must be the prover's. ([RFC 9449](https://datatracker.ietf.org/doc/html/rfc9449); [WorkOS DPoP](https://workos.com/blog/dpop-rfc-9449-explained))
- **mTLS-bound tokens:** the token is bound to the client *certificate* used on the TLS connection. Since proxy mode has the prover hold the TLS keys, an mTLS client cert *could* in principle be presented, but this is operationally heavy and rare for consumer APIs.
- **Reality check (good news):** as of 2026, **most large consumer APIs still issue plain bearer tokens.** DPoP/mTLS is concentrated in **FAPI 2.0 / open banking, SMART-on-FHIR (health), eIDAS 2.0, and Bluesky/atproto (which mandates DPoP on every request)**. So "prove your bank balance" or "prove a Bluesky fact" hits the binding blocker; "prove a GitHub/streaming/social fact" generally does not. ([AquilaX sender-constrained tokens](https://aquilax.ai/blog/sender-constrained-tokens-dpop-mtls); [carrierintegrations DPoP](https://www.carrierintegrations.com/sender-constrained-tokens-how-dpop-solves-the-bearer-token-security-crisis-in-production-carrier-api-integrations/))

---

## 3. CRITICAL nuance — single-phone warm user: app-switch OAuth vs system-browser cookie reuse

**Verdict: when the fact is in an OAuth scope, app-switch OAuth wins on a warm/returning user (≈ tie on a single first run); but "OAuth exists" frequently does NOT mean "the fact is in scope," and when it isn't you are forced onto the cookie/web path — which on iOS carries an unavoidable consent sheet.**

**Tap/second comparison (single phone, warm user, iOS):**

| | App-switch OAuth (fact in scope) | System-browser cookie reuse (web-only fact) |
|---|---|---|
| First run (cold consent) | tap *Continue* → app-switch → Face ID → **consent screen** → back: **2–3 taps, ~5–10 s** | tap *Continue* → **"…wants to use site to Sign In" sheet (Continue)** → page already logged in → back: **2–3 taps, ~5–12 s** |
| Returning run | tap *Continue* → app-switch → Face ID → back (**consent auto-skipped**): **1–2 taps, ~5–8 s** | iOS **still shows the sheet every time** (it gates cookie sharing): **2–3 taps, ~5–10 s** |
| Credential | Bearer token → notarize API JSON directly | Web cookie → notarize the authenticated web response |

So on a **warm returning iOS user, app-switch OAuth is ~1 tap and a few seconds cheaper**, mostly because the consent screen disappears on repeat runs while the iOS cookie-sharing sheet does not. ([consent skip](https://developers.google.com/workspace/guides/configure-oauth-consent); [iOS sheet is mandatory for cookie reuse](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/prefersephemeralwebbrowsersession))

**On Android the gap narrows:** Chrome Custom Tabs reuse the Chrome cookie jar **with no prompt**, so cookie reuse is as low-friction as OAuth (2–3 taps, no scary sheet). ([CCT cookie jar](https://steamclock.com/blog/2025/05/android-chrome-custom-tabs/))

**The scope trap (this is the part teams get wrong):** the decision is *gated by whether the fact is exposed in any OAuth scope at all.* Concrete, current example — **the canonical "prove Spotify Premium" demo no longer works via OAuth**: Spotify **removed the `product` field (which held `premium`/`free`) from the Get Current User's Profile endpoint in the February 2026 Web API changes**, along with `country` and other profile fields. There is now **no OAuth scope that returns subscription tier**, so proving Spotify Premium is **forced onto the authenticated-web (cookie) path** — exactly the case where you cannot avoid the cookie flow. ([Spotify Feb-2026 changelog](https://developer.spotify.com/documentation/web-api/references/changes/february-2026); [migration guide](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide); [rspotify issue #550](https://github.com/ramsayleung/rspotify/issues/550))

**Practical rule:**
1. If the target fact is reachable via a documented OAuth scope **and** the token is a plain bearer → **prefer app-switch OAuth** (fewest taps for warm users, cleanest redaction: redact one `Authorization` header).
2. If the fact is web-only (no scope, scope removed, or behind DPoP you can't satisfy) → **cookie reuse is the only path**; accept the iOS sheet, lean on Android's silent CCT.
3. Never assume (1) — verify the exact field is in a live scope before designing the flow.

---

## 4. Recommended offer-ordering for a single-page mobile flow

**Warm/cold detection first:** attempt a silent capability probe per target — (a) is the target's native app installed (universal-link / package check)? (b) does the user have a live web session (cheap unauthenticated probe of an endpoint that 302s when logged out)? (c) does the RP advertise passkeys (conditional-UI `mediation: "conditional"`)? Use the result to pick the *single* primary CTA; hide the rest behind "Other ways to connect."

**Primary order (mobile, single page), highest→lowest "wow," gated by the §3 scope check:**

1. **App-switch OAuth + PKCE** — *only if the fact is in a plain-bearer OAuth scope and the target app is installed.* Fewest taps for warm/returning users (1–2), cleanest proof (redact one header).
2. **System-browser cookie reuse** — default when the fact is web-only or scope-less. On **Android** this is near-frictionless (silent CCT cookie jar); on **iOS** it costs the one consent sheet. This is the **Spotify-Premium-class** path.
3. **Sign in with Apple/Google** — only when the *fact itself* is an Apple/Google-held fact (verified email, etc.); otherwise it's just identity, not a notarizable fact. Fast (One Tap 1.4 s) when applicable.
4. **Passkey same-device** — when the **target platform** supports passkeys and we can capture *its* session; great UX (3–8.5 s) but auth is to the RP, so only useful if that RP == target.
5. **SMS OTP** — fallback when no session/app/passkey exists; lean on iOS Security Code AutoFill + Android SMS Retriever to keep it ~1 tap to fill.
6. **Email OTP (code, not link)** — fallback below SMS; keep the code in-context, never use a magic link as the happy path (tab-switch cost + session-context split).
7. **FIDO CDA / QR cross-device** — only for **desktop-originated** flows where the prover runs on the desktop; not a primary mobile-single-page option.
8. **Manual password** — never the happy path (anti-goal).

**Two hard rules baked into ordering:** (a) the primary CTA is always whichever produces a *directly notarizable credential in the prover's own context* with the fewest taps; (b) if the only way to a fact is QR cross-device or a remote-auth endpoint, require **explicit consent** and scope the captured token to the single proof — see risks.

---

## 5. Open risks / what I couldn't verify

- **TLS 1.3 support in shipped proxy mode.** Public TLSNotary material repeatedly cites **TLS 1.2 + `TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256`**. Many modern endpoints are **TLS-1.3-preferred or TLS-1.3-only**; I could not confirm current proxy-mode TLS 1.3 coverage (the tlsnotary.org docs and the arXiv review are **Cloudflare-403** to WebFetch, so I relied on search summaries). **Verify against the running prover before committing to any specific target.** ([proxy-mode blog](https://tlsnotary.org/blog/2026/04/22/proxy-mode/))
- **Exact warm-user second counts are partly EST.** Hard numbers exist for passkey (8.5 s), One Tap (1.4 s), proxy-mode latency, and the OTP-vs-magic-link delta (~14 s). App-switch-OAuth, cookie-reuse, FIDO-CDA, and email-OTP *wall-clock* figures are triangulated estimates from mechanism behavior, not measured studies — treat as design assumptions, validate with our own instrumentation.
- **Cookie durability under replay.** Whether a captured web session cookie survives replay from a *new* TLS session depends on per-site binding (UA pinning, IP heuristics, device fingerprint, sliding rotation, CSRF tokens on writes). Must be tested per target; some sites will reject the replayed request even with a valid cookie.
- **DPoP/mTLS exposure per target.** I confirmed DPoP is rare in consumer APIs but mandatory in FAPI 2.0 / open banking / SMART-on-FHIR / **Bluesky atproto**. For any *financial, health, or Bluesky* fact, assume the bearer-replay path is blocked and budget for in-proof DPoP signing or a different approach. ([RFC 9449](https://datatracker.ietf.org/doc/html/rfc9449))
- **Spotify-style API erosion is a moving target.** The Feb-2026 removal of `product`/`country` shows platforms actively stripping fields from OAuth; a fact that's "in scope" today can vanish, silently forcing the cookie path. Build the flow to **fall back from OAuth→cookie automatically.**
- **Anti-goal compliance for remote-auth/QR flows.** QR cross-device and any "scan to authorize" endpoint can mint a session token that a server could capture and reuse — this is the silent-exfiltration anti-goal. I did not find a TLSNotary-native pattern that scopes such a token to a single proof; **this needs a product-side design** (explicit consent UI + token used once, client-side, then discarded). Flag for the lead researcher.
- **Server-side credential custody.** Any architecture where REP holds the user's cookie/token server-side (vs. on-device prover) is a privacy red flag; the on-device extension model (headers never leave the browser) is the privacy-preferred design and should be the default. ([TLSNotary extension: "never sends credentials to external servers"](https://tlsnotary.org/docs/extension/))
