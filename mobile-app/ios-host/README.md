# REP iOS host-shell (native SwiftUI, mock-first)

Items **①–④** of `mobile-app/PLAN.md`: the opening/onboarding flow for the GitHub
hero. **Runs on the simulator/iPhone right now with mocks** — no Rust prover, no
OAuth app, no rep.xyz needed. That's the "does the open feel fast" gate.

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
5. Re-open → "Your context" now lists the claim.

Tap timings/events are written to `Documents/proof-attempts.jsonl` per
`test-kit/measurement/event-spec.md` (read via `ProofAttemptCapture`).

## Hacks in this slice
| Hack | Where |
|---|---|
| 1 — pre-warm (reduced; PKCE + DNS/TLS warm, see OQ2) | `Sources/Net/Prewarm.swift` |
| 3 — pre-sheet explainer | `Sources/Views/PreSheetView.swift` |
| 4 — Universal Link auto-return | `Sources/Auth/Auth.swift` (`UniversalLinkRouter`) + `Resources/REP.entitlements` + `ServerTemplates/apple-app-site-association` |
| 6 — notarize-in-animation | `Sources/Views/ConnectGitHubView.swift` (`ConnectFlow.notarize`) |
| 2 — Keychain+Face ID (item ⑥), 5 — passkey probe (item ⑦) | not in this slice |

## Going real (later items)
- **OAuth (OQ9):** create a GitHub OAuth App (github.com/settings/developers), **enable "Issue refresh tokens"**, set callback `https://rep.xyz/oauth/github/callback`, put the Client ID in `Config.githubClientID`, set `Config.useMockAuth = false`. Real `ASWebAuthenticationSession` https-callback needs **iOS 17.4+** (mocks cover older dev devices).
- **AASA (Hack 4):** host `ServerTemplates/apple-app-site-association` at `https://rep.xyz/.well-known/` (replace `TEAMID`). For direct Xcode runs, use `applinks:rep.xyz?mode=developer` in the entitlement to skip Apple's CDN.
- **Notary + prover (OQ8/OQ6, item ⑧):** run `tlsnotary/notary-server` (Docker) allow-listing `api.github.com`, point `Config.verifierURL` at it; build the prover **xcframework**, add `Sources/TLSN/UniFFIProver.swift`, uncomment the framework in `project.yml`, set `Config.useMockProver = false`.
