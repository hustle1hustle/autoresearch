# Stage 1 — Login mechanism catalog, ranked by friction

Numbers reused/verified from `research/v1/01-auth-flows.md` (sources there). Ranked **strictly by friction** (warm user); the Stage-0 contract fit is a **separate column** — note how the lowest-friction method (Sign-in-with-Apple/Google) often *fails* the contract, which is exactly why the Stage-3 router doesn't just pick the top row.

**Friction score (transparent heuristic, lower = better):**
`F = taps + seconds/4 + (typing? 5) + (app-switch? 1) + (2nd device? 4)` — using warm mid-point seconds. It's a reproducible ordering device, not physics.

## Ranked catalog (warm user)

| Rank | Method | Taps | Sec | Typing | App-switch | 2nd dev | **F** | Credential yielded | **Stage-0 fit** |
|---|---|:--:|:--:|:--:|:--:|:--:|:--:|---|:--:|
| 1 | **Sign in with Apple / Google** (One Tap) | 1–2 | 1.4 | no | sheet | no | **~2.4** | OIDC `id_token` (Apple/Google-scoped) | **✗** usually no *target* credential (✓ only if target = Google/Apple) |
| 2 | **Passkey same-device** (conditional UI) | 1–2 | 3–8.5 | no | no | no | **~3.3** | session at the passkey's RP | **✓ iff RP = target**, else ✗ |
| 3 | **System-browser cookie reuse** (Android CCT) | 1–2 | ~5 | no | no | no | **~3.5** | **target cookie jar** | **✓✓** (warm path) |
| 3b | …same on **iOS** (`ASWebAuthenticationSession`) | 2 | 5–12 | no | sheet | no | **~4** | target cookie jar | **✓✓** (one consent sheet) |
| 4 | **App-switch OAuth + PKCE** (warm/returning) | 1–2 | 5–8 | no | yes→auto-return | no | **~4.5** | **target bearer** | **✓✓** (✗ if DPoP/mTLS-bound) |
| 5 | **FIDO CDA** (phone→desktop) | 2–3 | 10–20 | no | no | **yes** | **~10** | session on the **desktop** RP | ✓ (desktop-only context) |
| 6 | **QR cross-device** | 3–5 | 10–40 | no | no | **yes** | **~14** | session on the **other screen** | ⚠ prover must be there + anti-goal |
| 7 | **SMS OTP** | 3–5 | 15–40 | yes (autofill) | →Messages | no | **~16** | target session | ✓ |
| 8 | **OAuth device grant** (RFC 8628) | 4–6 | 20–40 | yes (code) | yes | no | **~18** | target bearer | ✓ but built for input-constrained devices |
| 9 | **Magic link** (email) | 4–6 | 45–60 | no (click) | →inbox | no | **~20** | session in *link's* context | ⚠ context-split risk |
| 10 | **Email OTP** (code) | 4–6 | 30–45 | yes | →inbox | no | **~20.5** | target session | ✓ |
| 11 | **Manual password** | 10+ | 30–90 | **heavy** | no | no | **~30** | target session | ✓ but **anti-goal** |

## Reading the ranking
- **Friction-rank ≠ router-pick.** Rows 1–2 (SiwA/Google, passkey) are the *lowest friction* but are **conditionally compatible**: SiwA/Google rarely yields a *target* credential; a passkey only helps if its RP *is* the target. So the **lowest-friction method that reliably satisfies the contract is the warm cookie-reuse / app-switch-OAuth band (rows 3–4)** — that's the router's real top tier.
- **The cliff is typing + second device.** F jumps ~3× from row 4 (~4.5) to rows 5–7 (10–16) the moment a method needs a **2nd device** (FIDO CDA, QR) or **typing** (SMS/email OTP). Everything above the cliff is "zero-typing, one device"; everything below kills the funnel proportionally.
- **iOS vs Android split is concentrated in row 3:** Android Custom Tabs reuse Chrome's cookie jar **silently**; iOS `ASWebAuthenticationSession` reuses Safari's cookies but **forces one consent sheet** (Stage 2 dissects this — it's the warm-reuse lever *and* the Spotify-`WKWebView` story).
- **Warm vs cold:** these are warm numbers. **Cold** = the user isn't logged into the service yet → prepend a one-time login sub-flow (+10–60 s, +2–6 actions), which mostly degrades rows 3–4 into "do a full login first." Passkey-cold adds passkey *creation* (+30–60 s). Hence Stage 2/3 lead with **warm-state detection.**

## Methods that survive into the router (contract-satisfying, zero-typing, one-device)
**Tier-A blades:** (3) warm system-browser cookie reuse, (4) app-switch OAuth, (2) passkey *when RP = target*. **Tier-B fallbacks (typing/second device):** SMS OTP → email OTP. **Edge:** FIDO CDA / QR only for desktop-originated flows; device grant only for input-constrained devices; password never. SiwA/Google: kept *only* as a target-is-Google/Apple special case, never as the generic blade.
