# Build Plan — REP iOS host-shell (native SwiftUI)

Agent plan answering the hand-off's 3 asks: **(a)** files I create + order, **(b)** what's delegated to the Mac, **(c)** open questions beyond the 5. Plus the resolved Q1/Q2 and the key de-risking decision so you can **feel the opening UX on your iPhone fast**.

## Resolved up front (from `tlsnotary/tlsn-extension` source)
- **Q1 — mode support: proxy = YES, MPC = YES.** We ship **Proxy** default, MPC fallback on 403/WAF. (`tlsn-mobile/src/lib.rs:187-190`, `prover.rs:44-45`, `TlsnNativeModule.swift:69-77`, settings toggle.) The hacks' ~1–2 s notarize assumption stands.
- **Q2 — no separate `connect()`.** Prover API = one-shot `prove()` + two-phase `proveUntilReveal()`→`proveFinalize(approved)`. WebSocket connect is fused with sending the (post-OAuth) request ⇒ **Hack 1 true pre-warm not implementable without forking**. We do a host-side micro-prewarm (PKCE + DNS/TLS warm, ~100–300 ms). **Hack 6 unaffected.**

## Architecture decision (the important one)
The spec mandates **native SwiftUI** and "don't modify the TLSN build; host-shell is a wrapper." The TLSN prover already exists as a **UniFFI Rust library** (`tlsn-mobile` crate) exposed to Swift as top-level symbols (`initialize`, `prove`, `proveUntilReveal`, `proveFinalize`, `HttpRequest`, `ProverOptions`, `Handler`, `Mode.proxy`, `ProofResult`, …). So:

- **Host-shell = a fresh SwiftUI app** that links the prover as an **`.xcframework`** and calls its Swift API. We reuse `app/mobile`'s Rust build output; we do **not** reuse its React-Native UI.
- **The prover is wrapped behind one Swift protocol** `TLSNProving`. Ship **two impls**: `MockProver` (returns a realistic GitHub `ProofResult` after a tunable delay) and `UniFFIProver` (the real xcframework). **This is the de-risk:** the entire opening/onboarding UX (Hacks 3/4/6 UI, ContextView, ConnectGitHubView, stage-progress, success, "what was proved") runs on `MockProver` with **zero dependency on the Rust build**, so you can build + feel it on your iPhone *now*; we swap in `UniFFIProver` once the xcframework is dropped in `test-kit/tlsn-build/ios/`.
- **Project generation via XcodeGen** (`project.yml`) so there's no hand-written `.pbxproj` to rot — Mac runs `xcodegen generate`.
- **Perf/"flies":** nothing heavy on cold start. `@main` shows `ContextView` immediately; `initialize()` (prover) + DNS/TLS warm run lazily in `.task` off the first interactive screen; no biometric/push prompt at launch (anti-goal); SwiftUI-only first paint.

## (a) Files I'll create, in order (by shippability — week-1 hacks first)
```
mobile-app/ios-host/
  project.yml                         # XcodeGen spec (bundle id, iOS 17, entitlements, frameworks)
  README.md                           # Mac build steps
  Sources/
   App/REPApp.swift                   # @main, scenePhase, lazy init, UniversalLink routing
   App/Theme.swift                    # color/type/“stage” tokens (✓/●/○), no “Loading”
   TLSN/TLSNProving.swift             # protocol: prove(request,options)->Claim ; proveUntilReveal/finalize
   TLSN/MockProver.swift              # realistic GitHub result + tunable latency  ← UX testable now
   TLSN/UniFFIProver.swift            # real impl over xcframework (compiled only when build present)
   TLSN/ModeRouter.swift              # proxy default; 403/Cloudflare -> MPC
   Auth/PKCE.swift                    # S256 verifier/challenge
   Auth/OAuthService.swift            # ASWebAuthenticationSession + GitHub authorize/token (PKCE)
   Auth/TokenStore.swift              # Keychain SecAccessControl(.biometryCurrentSet)  (Hack 2)
   Auth/UniversalLinkRouter.swift     # Hack 4: .onOpenURL / onContinueUserActivity dispatch
   Net/Prewarm.swift                  # Hack 1 (micro): PKCE pre-gen + DNS/TLS warm to verifier
   Views/ContextView.swift           # entry “Your context”, Prove again (warm-returning 1-tap)
   Views/ConnectGitHubView.swift     # connect screen; .task prewarm+probes; CTA
   Views/PreSheetView.swift          # Hack 3 explainer (.presentationDetents([.medium]), @AppStorage once)
   Views/StageProgressView.swift     # named steps Connecting→Confirming→Sealing (anti-spinner)
   Views/ProofSuccessView.swift      # success + expandable “What was proved” (uses RevealPreparation)
   Views/PasskeyProbe.swift          # Hack 5 conditional UI (REP-self only)
   Models/ProofClaim.swift           # claim schema (subject/account/predicate/value/source/evidence)
   Models/ContextGraph.swift         # on-device store of minted claims (the list on entry)
   Instrumentation/Analytics.swift   # event-spec wiring (from measurement/capture-ios.swift.snippet)
  Resources/
   Info.plist                        # LSApplicationQueriesSchemes (canOpenURL probes), ATS
   REP.entitlements                  # applinks:r3p.xyz, webcredentials:r3p.xyz
  ServerTemplates/
   apple-app-site-association        # AASA template (Hack 4) to host at r3p.xyz/.well-known/
```
**Order:** ① scaffold (project.yml, REPApp, Theme, `TLSNProving`+`MockProver`, Models) → ② ConnectGitHubView + PreSheetView(H3) + StageProgressView → ③ OAuthService+PKCE + UniversalLinkRouter(H4) + AASA/entitlements → ④ Notarize-in-animation(H6) wiring + ProofSuccessView/“what was proved” → ⑤ Prewarm(H1 micro) → ⑥ TokenStore biometry(H2) + ContextView warm-returning → ⑦ PasskeyProbe(H5) → ⑧ UniFFIProver swap + Analytics throughout. ①–④ = your first on-device build (mock prover) to test the opening UX.

## (b) Delegated to you on the Mac
1. Build the prover **`.xcframework`** from `tlsn-mobile` (reuse `app/mobile/build.sh` Rust output + uniffi-bindgen; package standalone) → drop in `test-kit/tlsn-build/ios/`. *(If you'd rather, the dev who offered help can produce this once.)*
2. `brew install xcodegen` → `xcodegen generate` → open in Xcode; sign with your **free Apple ID**.
3. Fill real config: GitHub OAuth **Client ID**, verifier URL (`https://demo.tlsnotary.org` to start), bundle id, `applinks:` domain.
4. Host **AASA** at `https://r3p.xyz/.well-known/apple-app-site-association` + the GitHub OAuth callback page (`/oauth/github/callback`). (Verifier service is a separate deliverable.)
5. `xcodebuild`/run on **Simulator** (0-account) and your **iPhone** (USB, free signing); confirm Q1 on device (mode:'Proxy' notarize), then fill `test-kit/comparison/template.csv` + Q4 wall-clock table.

## (c) Open questions beyond the 5
- **OQ-6: prover packaged as a standalone `.xcframework`?** Today the UniFFI symbols are consumed *inside* the Expo module. The native app needs them as a plain framework (the `tlsn_mobile.swift` bindings + the Rust static lib). Confirm `build.sh` can emit/relocate that, or we add a small packaging step. *(Blocks `UniFFIProver`, not the mock UX.)*
- **OQ-7: one-shot vs two-phase for the 1-tap hero.** `prove()` (one call, fastest, no extra tap) vs `proveUntilReveal`→`proveFinalize` (shows reveal previews but adds an approve step). Decision: **hero warm path uses one-shot `prove()`** (1 tap), and we render "What was proved" *after* from the returned `ProofResult`; reserve the two-phase flow for an optional "review before reveal" toggle. Confirm with PM.
- **OQ-8: verifier domain allow-list.** Does `demo.tlsnotary.org` (proxy mode) connect out to `api.github.com`? Tier-1 should be fine; verify on first device run, else point verifier at our own.
- **OQ-9: GitHub "issue refresh tokens" is per-OAuth-App opt-in** (target.md step 1.5). If off, Hack 2 silent-refresh degrades to full OAuth on re-open — confirm the app setting.

---
**Net:** I start with ①–④ now (SwiftUI host-shell + MockProver) so you get a buildable, *fast* opening flow on your iPhone before the Rust xcframework is even ready; the prover swaps in behind one protocol. Confirm the architecture (native SwiftUI + xcframework + mock-first) and OQ-7, and I'll begin writing the Swift.
