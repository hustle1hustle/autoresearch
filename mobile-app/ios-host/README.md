# REP iOS host-shell (native SwiftUI, mock-first)

Items **①–④ + ⑥** of `mobile-app/PLAN.md`: the opening/onboarding flow for the
GitHub hero, including the **warm-returning 1-tap (Face ID) path**. **Runs on the
simulator/iPhone right now with mocks** — no Rust prover, no OAuth app, no rep.xyz
needed. That's the "does the open feel fast" gate.

> **Simulator: enable Face ID** for the warm-returning path — **Features ▸ Face ID ▸ Enrolled**, then use **Features ▸ Face ID ▸ Matching/Non-matching Face** when the prompt appears. Without an enrolled biometric the Keychain item can't be created, so the app falls back to a fresh connect (by design).

## Build & run (Mac)
```bash
brew install xcodegen          # one-time
cd mobile-app/ios-host
xcodegen generate              # creates REP.xcodeproj
open REP.xcodeproj             # Xcode → pick your (free) Apple ID team in Signing
# Run on a Simulator (no account) or your iPhone (USB, free signing).
```
`Config.useMockProver` and `Config.useMockAuth` are **ON** → the whole flow works offline.

## What you'll see
1. **Your context** (empty) → tap **Connect GitHub**
2. **Pre-sheet** explainer (Hack 3, first run only) → **Continue with GitHub**
3. Mock auth handoff (~0.6 s) → **mint** (~1.6 s; hidden under the snappy transition, Hack 6 — if it ever overruns 2 s you'll see the named **Connecting → Confirming → Sealing** stages, never a spinner)
4. **Proof minted · octocat · 1,247 contributions** → **Share** / **What was proved** (expandable)
5. Re-open → "Your context" lists the claim. **Tap it → Face ID → ~3–4 s → success** — the warm-returning **1-tap** hero path (Hack 2 + 6, 0 app-switches).

Tap timings/events are written to `Documents/proof-attempts.jsonl` per
`test-kit/measurement/event-spec.md` (read via `ProofAttemptCapture`).

## Hacks in this slice
| Hack | Where |
|---|---|
| 1 — pre-warm (reduced; PKCE + DNS/TLS warm, see OQ2) | `Sources/Net/Prewarm.swift` |
| 3 — pre-sheet explainer | `Sources/Views/PreSheetView.swift` |
| 4 — Universal Link auto-return | `Sources/Auth/Auth.swift` (`UniversalLinkRouter`) + `Resources/REP.entitlements` + `ServerTemplates/apple-app-site-association` |
| 6 — notarize-in-animation (shared) | `Sources/Flow/Notarizer.swift` (used by connect + reprove) |
| 2 — Keychain + Face ID (warm-returning 1-tap) | `Sources/Auth/KeychainTokenStore.swift`, `Sources/Flow/ReproveFlow.swift` |
| 5 — passkey probe (item ⑦) | not in this slice |

## Going real (later items)
- **OAuth (OQ9):** create a **GitHub App** — *not* a classic OAuth App; refresh tokens (Hack 2) only work with GitHub Apps (`test-kit/setup/02-oauth-apps.md` §A). Callback `https://rep.xyz/oauth/github/callback`; put the `Iv1.…` Client ID in `Config.githubClientID`; set `Config.useMockAuth = false`. Code→token + refresh run on the **REP backend** (client secret off-device). Real `ASWebAuthenticationSession` https-callback needs **iOS 17.4+** (mocks cover older dev devices).
- **AASA (Hack 4):** host `ServerTemplates/apple-app-site-association` at `https://rep.xyz/.well-known/` (replace `TEAMID`). For direct Xcode runs, use `applinks:rep.xyz?mode=developer` in the entitlement to skip Apple's CDN.
- **Notary + prover (OQ8/OQ6, item ⑧):** run a notary that allow-lists `api.github.com` (`test-kit/setup/03-self-hosted-notary.md` — the PSE hosted notary won't), point `Config.verifierURL` at it; build the prover **xcframework** (`test-kit/setup/01-xcframework-build.md`), drop it in `test-kit/tlsn-build/ios/`, uncomment the framework in `project.yml`, set `Config.useMockProver = false`. **`Sources/TLSN/UniFFIProver.swift` is already written** (guarded by `#if canImport(TlsnProver)`) — it activates automatically once the framework is linked.
