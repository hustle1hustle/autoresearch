# REP Mobile App — Research

**Дата.** 2026-06-03. **Контекст.** TLSNotary mobile UX research bundle для kickoff'а mobile app implementation. Это обоснования всех решений в `SPEC.md`.

**Method.** Cloned `tlsnotary/tlsn` source, built and timed examples locally, fetched primary blog posts and SDK docs, cross-referenced Reclaim / Primus / Plaid / Apple Wallet / Privy. Numbers cited or marked `[ASSUMPTION + source]`.

---

## TL;DR — что нашли неожиданного

1. **TLSNotary GA mobile app не существует.** Их iOS prover в экспериментальном `tlsnotary/ios-wasmtime` branch, упирается в открытый Wasmtime iOS issue ([bytecodealliance/wasmtime#5754](https://github.com/bytecodealliance/wasmtime/issues/5754)). Primary distribution = [Chrome extension](https://chromewebstore.google.com/detail/tlsnotary/gnoglgpcamodhflknhmafmjdahcejcgg). Значит REP не "побеждает" их аппку, а становится канонической.
2. **Warm returning user МОЖЕТ быть 1 тап.** Stored refresh token + Face ID + auto-fired notarize, с ~1-2 с notarize прячущимся под OAuth-return animation. Первый proof — 2 тапа, второй и далее — 1 тап.
3. **Silent warm-detection на iOS почти мёртв post iOS 9.** `canOpenURL` allowlist'ом (cap 50 schemes), Universal Link installability, conditional UI passkey probe — это всё что осталось. Hidden WebView session probing = anti-goal violation.
4. **Reclaim использует WKWebView для cookie capture** (включая HttpOnly). Pattern portable в native SwiftUI host, не Reclaim-proprietary.
5. **Pre-sheet объяснение перед iOS consent sheet даёт +15-25 п.п. конверсии.** На Android Chrome Custom Tabs шарят cookies silently, pre-sheet опционален.
6. **Spotify tier proof МЁРТВ post-Feb-2026.** Поле `product` удалено из `/v1/me`, dev mode capped at 5 users, Extended Quota требует 250k MAU. Listening history endpoints выживают. Cookie path grey ToS.

---

## 1. TLSNotary infra. mode routing

**Источник.** Cloned `tlsnotary/tlsn` source at `crates/examples/{proxy/proxy.rs, basic/basic.rs}`, fetched [proxy-mode blog](https://tlsnotary.org/blog/2026/04/22/proxy-mode/) и [bench post](https://tlsnotary.org/blog/2026/05/10/blog-proxy-mode/).

### Two modes (binary toggle)

**MPC mode** (gold standard). Prover и verifier jointly run TLS handshake через MPC. Никто не holds full keys. Even malicious prover не может forge данные. **Prover's device connects to server** → request от user's residential/mobile IP. Verifier не learns server во время online phase.

- Cost. ~13 с preprocessing floor + heavy bandwidth. Прибл. **30 MB GC upload** на 1 KB request / 2 KB response.
- Network sweep. **52 с @ 5 Mbps → ~1 с @ 1 Gbps** для 30 MB upload.
- Latency sweep. **13.3 с @ 200 ms RTT vs 6.2 с proxy** (2x at high-latency).
- Browser MPC дополнительно needs WebSocket↔TCP proxy hosted somewhere.

**Proxy mode** (Apr 2026, the fast workhorse). **Verifier connects to server** и forwards encrypted TLS. ZK proof verified after session. Browser-clean (нет separate relay).

- Cost. **~1-2 с** для 1-2 KB exchange. **Flat по payload** (1 KB → 51 KB поменяло время с ~1.6 с до ~1.6 с).
- Tradeoff. **Server sees verifier's IP, not user's.** Datacenter IP может быть flagged.

### Mode-selection decision table

| Что у data endpoint'а | Mode | Почему |
|---|---|---|
| Public/dev JSON API (`api.github.com`, `api.strava.com`, `api.anthropic.com`, `api.wise.com`) | **Proxy** | Token-rate-limited, не IP-flagged. Get ~1-2 с win. |
| Consumer surface за Cloudflare/Akamai/Imperva/PerimeterX/DataDome | **MPC** | Datacenter IP заблочат. Use user residential/mobile IP. ~13 с floor. |
| Device-attested (Play Integrity, DeviceCheck, App Attest) — Revolut retail, hardened bank apps, IG/TikTok mobile | **Не строим** | Ни proxy ни MPC не помогают. App attestation требует genuine unmodified app. |
| Strongest guarantee, adversarial prover | **MPC** | Cryptographic authenticity even vs malicious prover. |
| Browser/mobile-web, минимум хостить | **Proxy** | Verifier держит и WebSocket и TCP. Нечего ставить дополнительно. |

### Residential proxy nuance

Можно роутить proxy mode через residential proxy чтобы получить юзер-like IP при скорости proxy. Но это:
- Inserts third-party в network path кто мог in principle interpose → **ломает единственное security предположение proxy mode**
- Re-introduces vendor dependency что мы explicitly avoid

**Иерархия для flagged target.** MPC (user-IP, no extra trust) > proxy via residential (fast, weaker trust, vendor) > datacenter proxy (заблочат).

Reclaim основан на residential routing precisely потому что их attestor-as-proxy model exposes same IP. Мы не делаем residential default.

### Verified facts ledger (from research bundle)

| Claim | Verdict | Source |
|---|---|---|
| Proxy mode = verifier connects к server, forwards encrypted TLS, ZK proof verified after | ✅ | `crates/examples/proxy/proxy.rs:215` (`TcpStream::connect`) + proxy-mode blog post |
| Proxy ~1-2 с для 1-2 KB | ✅ | Bench post May 10. ~1.6 с full-reveal |
| MPC ~3-15 с. heavy bandwidth (GC + OT, multi-round) | ✅ | ~13 с preprocess floor, ~30 MB upload |
| MPC. no party holds full keys, request from user IP | ✅ | `SessionKeys` split (`mpc-tls/lib.rs:42-54`), prover connects (`basic.rs:101`) |
| Proxy. server sees verifier IP | ✅ | `proxy.rs:215` + topology assumption в proxy-mode blog |
| Browser MPC needs WS↔TCP proxy. proxy mode is "browser-clean" | ✅ | Harness README + proxy-mode blog |
| Two modes toggleable | ✅ | `VerifierCommitStart::{Mpc, Proxy}` enum |
| Notary supports JWT bearer auth | ✅ | notary-server docs (separate repo) |
| Prover может present X.509 client certs | ✅ | `attestation/prove.rs:118` (`CLIENT_CERT_DER`) |
| PSE's hosted proxy whitelists domains → self-host для arbitrary targets | ✅ | notary_server docs |

---

## 2. Auth-flow matrix

**Source.** [FIDO Passkey Index 2025](https://fidoalliance.org/passkey-index-2025/), [Google One Tap guide](https://securityboulevard.com/2025/09/the-complete-guide-to-google-one-tap-login-everything-developers-need-to-know/), [Apple ASWebAuthSession docs](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession), [Steamclock Android CCT writeup](https://steamclock.com/blog/2025/05/android-chrome-custom-tabs/).

### Warm user matrix (validated against sources)

| Method | Taps | Seconds | Main funnel-breaker | Source |
|---|---|---|---|---|
| Passkey same device (Face/Touch ID, conditional UI) | 1-2 | **3-5** | RP must support passkeys, key уже на device | FIDO Passkey Index 2025. ~3 с synced passkey vs 69 с password |
| Sign in with Apple / Google (OIDC) | 2 | **1.4-3** (One Tap median) | Service must offer; fact must be in scope | Google One Tap guide. 1.4 с median vs 6.3 с password+TOTP |
| App-switch OAuth + PKCE (target app installed) | 1-2 warm-repeat / 2-3 first | **5-10** | Consent screen (first time only — returning auto-skip) | Google Workspace OAuth docs. consent skip on repeat |
| System browser + cookie reuse (`ASWebAuthSession` iOS / CCT Android) | 2-3 | **5-12** | iOS scary system sheet (mandatory for cookie share); Android CCT silent | Apple `prefersEphemeralWebBrowserSession` docs |
| FIDO CDA (phone → desktop, QR + BLE) | 2-3 | 10-20 | 2nd device + BLE + passkey-сапорт | Corbado CDA explainer |
| SMS OTP | 3-5 | 15-40 | Delivery + entry (iOS autofill spases) | iOS Security Code AutoFill / Android SMS Retriever |
| QR cross-device (phone → desktop) | 3-5 (scan) | ~10 (Telegram) / 2-3 + sync (WhatsApp) | Two devices + scanner buried | Telegram qr-login API docs |
| Email OTP (code) | 4-6 | 30-45 | Switch to inbox app | Clerk study via Scalekit |
| Magic link | 4-6 | **45-60** | **Tab switch = top funnel killer**. ~14 с slower than OTP code | Clerk study, ProductAgency critique |
| Manual password | 10+ | 30-90 | Forgotten password (slip #1) | — |

**Cold user.** Add one-time login sub-flow (+10-60 с, +2-6 actions).

### Single-phone warm user. app-switch OAuth vs cookie reuse

| | App-switch OAuth (fact in scope) | System browser + cookie reuse (web-only fact) |
|---|---|---|
| First run | 2-3 taps, ~5-10 с (consent screen) | 2-3 taps, ~5-12 с (iOS sheet + already-logged-in page) |
| **Returning** | **1-2 taps, ~5-8 с** (consent auto-skipped) | 2-3 taps, ~5-10 с (iOS still shows sheet каждый раз) |

**Verdict.** App-switch OAuth wins для warm returning iOS user mostly because consent screen disappears on repeats, while iOS cookie-sharing sheet does not.

**Android.** Gap narrows. CCT cookie-jar sharing silent without prompt. На Android cookie reuse as low-friction as OAuth.

### The scope trap

"OAuth exists" ≠ easy. **If specific fact not exposed в OAuth scope, forced на bot-defended web (cookie) path.**

**Concrete current example.** Spotify Premium tier proof. **No longer works via OAuth** because Spotify removed `product` field from `/v1/me` in Feb 2026. ([Feb 2026 changelog](https://developer.spotify.com/documentation/web-api/references/changes/february-2026)). Forced на authenticated-web path.

### Token-binding blocker (DPoP, mTLS)

- **DPoP (RFC 9449).** Каждый resource request needs fresh proof-JWT signed by client's private key. Independent of transport connection. Если target API requires DPoP — prover must DPoP-sign inside notarized request (possible, complex).
- **mTLS-bound tokens.** Bound to client cert на TLS connection.

**Reality check.** Most large consumer APIs still issue plain bearer tokens. DPoP/mTLS concentrated в FAPI 2.0 / open banking, SMART-on-FHIR (health), eIDAS 2.0, Bluesky/atproto. **GitHub, streaming, social → plain bearer; Bluesky / bank → bound.**

### Recommended offer-ordering для single-page mobile flow

1. **App-switch OAuth + PKCE** — primary if fact in plain-bearer OAuth scope AND target app installed
2. **System-browser cookie reuse** — default when fact is web-only or scope-less
3. **Sign in with Apple/Google** — only when fact lives в Apple/Google APIs (rarely для third-party data)
4. **Passkey same-device** — when target RP supports passkeys
5. **SMS OTP** — fallback
6. **Email OTP (code, not link)** — fallback below SMS
7. **FIDO CDA / QR cross-device** — desktop-originated flows только
8. **Manual password** — never happy path (anti-goal)

---

## 3. Target tiering (с endpoint evidence)

**Source.** [GitHub OAuth docs](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/refreshing-user-access-tokens), [Strava API reference](https://developers.strava.com/docs/reference/), [Duolingo unofficial API docs](https://tschuy.com/duolingo/api/data.html), [Codeforces apiHelp](https://codeforces.com/apiHelp/methods), [Anthropic Admin API](https://platform.claude.com/docs/en/api/admin/cost_report), Reclaim provider catalog.

### Tier 1 — launch set (JSON-only, proxy-safe)

| # | Target | Fact | Endpoint | Auth | Mode | Reclaim? | ToS |
|---|---|---|---|---|---|---|---|
| 1 | **GitHub** ⭐ HERO | Contributions / streak / repos | `POST api.github.com/graphql` (batch fields) | OAuth `read:user` | Proxy | ✅ | Clean |
| 2 | Strava | Activities, stats, zones | `/v3/athlete` + stats + activities + zones | OAuth `activity:read` | Proxy | ✅ | Clean |
| 3 | Duolingo | Streak + totalXp | `/2017-06-30/users/{id}?fields=streak,totalXp,...` | Cookie reuse | Proxy (conditional) | ✅ | Grey (6-yr stable) |
| 4 | Codeforces | Rating, contests | `/api/user.info` + rating + status | None (public) + nonce-binding | Proxy | likely | Clean |
| 5 | StackOverflow | Reputation, badges, tags | `/2.3/me` + answers + tags | OAuth | Proxy | likely | Clean |
| 6 | LeetCode | Solved, contest rating | `POST /graphql` (matchedUser + contestRanking) | Cookie reuse | Proxy (conditional, CF risk) | likely | Grey |
| 7 | Anthropic Console | $ spend / token usage | `/v1/organizations/cost_report` + usage | Admin API key paste | Proxy | none | Clean |

### Tier 2 — value, medium friction (нужен residential/MPC или grey ToS)

Uber/Lyft (internal GraphQL, datacenter blocked → MPC/residential), Wise (personal token API exists, clean-ish), PayPal (business clean, consumer grey), Amazon order history (Reclaim-proven но HTML fragile + Cloudflare → residential/MPC).

### Tier 3 — avoid as core

X / Twitter (paid tier, free removed 2026), Instagram/TikTok/Meta (App Attest + DataDome + churn), Revolut retail (Play Integrity на endpoint), Ticketmaster (anti-bot by design, HTML), Spotify (post Feb-2026 lockdown).

### Tier 4 — moat (later, zkTLS killer case)

Gov / tax / health portals (no API, defensible-because-bespoke), но slow.

### Key finding. Spotify lockdown (Feb 2026)

- **`product` field removed from `/v1/me`** (Premium/free tier proof MЁRTV)
- **Dev mode capped at 5 users**, requires Premium dev account
- **Extended Quota requires 250k MAU** (closed to seed-stage products)
- Consumer web-player token via `sp_dc` cookie still works но grey ToS + Spotify deliberately hardening internal endpoints

→ **Spotify не в launch set**. Listening history only as v2 / "fun" proof.

### Reclaim's law (Tier-1 design principle)

Cited in their [zkTLS AI blog post](https://blog.reclaimprotocol.org/posts/zktls-ai). "JSON APIs have been observed to remain relatively constant, but HTML websites often change… when an XPath changes, the provider breaks, can stay broken for hours, sometimes days."

**Consequence.** Tier-1 = JSON-only. Any HTML/XPath target = maintenance liability.

---

## 4. Reference app teardowns

### TLSNotary mobile (benchmark to beat)

**State as of 2026-06.** No GA mobile app. iOS prover experimental in `tlsnotary/ios-wasmtime`. Chrome extension primary surface. Wasmtime iOS support open issue ([#5754](https://github.com/bytecodealliance/wasmtime/issues/5754)).

**Implication.** REP не "beats" non-existent TLSN mobile app — REP becomes the canonical mobile zkTLS app.

**One trick worth stealing (from Chrome extension).** [Extension docs](https://tlsnotary.org/docs/extension/) показывают raw request via interactive Developer Console. Transparency about commitments is the trust story. Mirror in REP's "What was proved" affordance.

### Reclaim Protocol mobile (closest direct competitor)

**Source.** [reclaim-inapp-ios-sdk GitHub](https://github.com/reclaimprotocol/reclaim-inapp-ios-sdk), [security FAQ](https://blog.reclaimprotocol.org/posts/security-faq).

**Mechanic.** SDK exposes `ReclaimVerification.startVerification(request)` который presents SwiftUI sheet hosting WKWebView. WebView navigates to provider site, user logs in **inside the sheet**, Reclaim's JS shim observes network response, captures cookie/header, generates ZK proof.

**Why WKWebView matters.** SDK has webview-level access including `HttpOnly` cookies and arbitrary JS injection. Security FAQ confirms.

**One trick to steal.** Inline WebView login для cookie-path targets. User не leaves host app, no Universal Link round-trip, no return animation glitches.

**One failure mode to avoid.** Reclaim's sheet shows their brand chrome heavily, can't be masked by host app developer. **REP должен design our sheet чтобы REP branding subtle и target platform's brand dominant.**

### Primus Labs mobile (secondary reference)

**Source.** [docs.primuslabs.xyz](https://docs.primuslabs.xyz/data-verification/developer-hub/), browser-extension-first.

**State.** No public iOS SDK with Reclaim's depth. Data template marketplace pattern worth borrowing for longer-tail expansion.

### Plaid Link iOS (gold standard for "log into 3rd party from inside our app")

**Source.** [Plaid Link iOS docs](https://plaid.com/docs/link/ios/), [OAuth guide](https://plaid.com/docs/link/oauth/), [Best Practices](https://medium.com/@FintegrationFS/plaid-link-best-practices-ux-conversion-tips-that-reduce-drop-off-in-bank-linking-c3b5fddf8930).

**Mechanic.** `Plaid.create()` preloads Link, `handler.open(presentUsing:)` presents. Institution picker → OAuth via Universal Link → callback to host. Event-driven (`OPEN`, `SELECT_INSTITUTION`, `OPEN_OAUTH`, `HANDOFF`, `onSuccess`).

**Tricks to steal.**
- **Preload pattern** (Hack 1 source)
- **Event-driven UX** для instrument'ирования каждого drop-off point
- **No interstitials** между key actions
- **Custom loading-state opt-out** (`noLoadingState = true`) host can show их brand during preload

**Failure to avoid.** Plaid heavily branded. REP должен be REP-subtle, target-prominent.

### Stripe Identity iOS (multi-step verify, premium feel)

**Source.** [Stripe Identity iOS docs](https://docs.stripe.com/identity/verify-identity-documents?platform=ios&type=new-integration).

**Tricks to steal.**
- **Automatic capture** (no manual shutter button) для "show your screen" affordances
- **One sheet, multiple steps** — back-button stays in-sheet. **REP's GitHub flow должен be single sheet, не navigation stack.**
- **Implicit progress без ceremony** — subtle step indicator

### Apple Wallet "Add card" (best-in-class native fast credential)

**Source.** [Apple Pay in-app provisioning demo](https://applepaydemo.apple.com/in-app-provisioning), [Lithic Push Provisioning](https://docs.lithic.com/docs/push-provisioning).

**Tricks to steal.**
- **System-managed UX you can't break** — once `ASWebAuthSession` takes over, trust system to handle it well. Don't try to skin.
- **Skip extra auth когда possible** — if user already auth'd to issuer app (OTP при install), Apple Pay не re-asks. **Mirror in REP.** once user minted any proof on device, biometric sufficient для next one (Hack 2).
- **Success notification** outside the flow.

**Failure to avoid.** Apple's HIG **forbids interstitials between button and system sheet**. Don't put REP-branded "About to add" screen между "Add to Apple Wallet" и system sheet. Generalizes. **Don't interstitial system-managed handoffs.**

### Privy / Web3Auth / Dynamic (Web2-feel social login для crypto)

**Source.** [Privy iOS SDK](https://github.com/privy-io/privy-ios), [Expo passkey docs](https://docs.privy.io/guide/expo/authentication/passkey).

**Tricks to steal.**
- **Explicit auth state machine surfaced to UI.** `initial` → `generating-challenge` → `awaiting-passkey` → `submitting-response` → `done`. **REP analog.** `connecting-to-verifier` / `auth-with-platform` / `notarizing` / `done`. **Никогда generic "Loading…".**
- **First proof bootstraps user's REP identity. subsequent proofs can use biometric reauth.** Same pattern.
- **Cross-platform consistency.** System passkey APIs give same feel everywhere.

---

## 5. Six hacks (with citations and savings)

Каждый хак с trick / source / savings (taps/sec) / iOS sketch / Android delta / what breaks it. См. `SPEC.md` § "6 хаков" для implementation-ready spec.

### Hack 1. Pre-warm WebSocket on screen mount

- **Trick.** Open WebSocket к verifier и generate PKCE до tap на CTA.
- **Source.** Plaid Link `Plaid.create()` + `onLoad` callback pattern.
- **Savings.** ~500-1000 ms perceived latency.
- **Stackability.** Hack 6 (notarize-in-animation) depends on this.

### Hack 2. Refresh token + Face ID

- **Trick.** Save OAuth refresh_token в Keychain под `.biometryCurrentSet`. Repeat. Face ID → silent grant → notarize.
- **Source.** [GitHub OAuth refresh docs](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/refreshing-user-access-tokens) + Apple `SecAccessControl` pattern.
- **Savings.** **2 taps → 1 tap, ~7 с → ~3-4 с** для repeat proofs.
- **What breaks.** GitHub token policy. access 8h, refresh 6 months, rotated on use. Re-enrollment Face ID invalidates item (feature, fall back).

### Hack 3. Pre-sheet explainer

- **Trick.** Перед `ASWebAuthSession` show one-screen explainer.
- **Source.** [Okta history of mobile SSO](https://developer.okta.com/blog/2022/01/13/mobile-sso) + [Plaid Best Practices](https://medium.com/@FintegrationFS/plaid-link-best-practices-ux-conversion-tips-that-reduce-drop-off-in-bank-linking-c3b5fddf8930).
- **Savings.** **+15-25 п.п. conversion через iOS system sheet** (`[ASSUMPTION + sources above]`).
- **Android.** Optional. CCT silent.

### Hack 4. Universal Link auto-return

- **Trick.** Configure OAuth redirect URI as Universal Link backed by AASA. iOS routes redirect into app automatically.
- **Source.** [Plaid iOS docs](https://plaid.com/docs/link/ios/) — "Universal Links… prevents arbitrary app interception".
- **Savings.** Prevents ~3-8 с manual swipe-back и ~30% drop-off (`[ASSUMPTION + Plaid implicit proof]`).
- **What watch.** TestFlight AASA fetch delay до 15 минут.

### Hack 5. Conditional UI passkey probe

- **Trick.** Fire `mediation: "conditional"` WebAuthn assertion в background. If user has passkey → iOS autofill chip.
- **Source.** Apple WWDC22 + [Corbado conditional UI](https://www.corbado.com/blog/webauthn-conditional-ui-passkeys-autofill).
- **Privacy.** RP не learns availability ([W3C webauthn#1862](https://github.com/w3c/webauthn/issues/1862)).
- **Savings.** Passkey 8.5 с vs 31.2 с MFA (73% faster, [FIDO Index 2025](https://fidoalliance.org/passkey-index-2025/)).
- **Limitation.** GitHub OAuth не accepts WebAuthn for token issuance. Applies to REP-self login + cookie-path targets if they support passkey.

### Hack 6. Notarize-in-animation

- **Trick.** After ASWebAuthSession success callback, iOS spends ~400 ms animating back. Kick GraphQL + proof в this window. User perceives "tap → done".
- **Source.** Plaid's "callback ordering is not guaranteed" pattern + [Nielsen Norman response time thresholds](https://www.nngroup.com/articles/response-times-3-important-limits/).
- **Savings.** Removes ~1-2 с notarize from perceived latency для warm runs.
- **Stack.** Hack 1 + Hack 2 + Hack 6 = warm returning 1 tap / ~3 с.

---

## 6. Anti-patterns library

### Loading + success states
- **"Spinner without context"** — `ProgressView()` без copy или "Loading…". **Fix.** Stage progress `✓ / ● / ○` с named steps.
- **"Did it work?"** — silent success. **Fix.** Explicit success state with fact + optional local push.
- **"What was just proved"** — green checkmark без revealing claim. **Fix.** Expandable "What was proved" card с request, revealed bytes, redacted bytes, нотариус, expiry.

### Auth handoff
- **"Lost in inbox"** — magic-link. **Fix.** Anti-goal. Magic-link не primary/secondary.
- **"Where did I come from"** — manual swipe back. **Fix.** Universal Link auto-return (Hack 4).
- **"Scary system sheet"** — iOS sheet в лоб. **Fix.** Pre-sheet (Hack 3).
- **"App-switch you can't trust"** — WKWebView для чужих паролей. **Fix.** NEVER. ASWebAuthSession (URL visible) или нативный app-switch.
- **"Branded sheet on third-party login"** — REP-брендинг during GitHub-пароля. **Fix.** Target brand dominant.

### Repeat use
- **"Re-prove every time"** — full OAuth каждый раз. **Fix.** Hack 2 (refresh + Face ID).

### Permission timing
- **"Permission requested before purpose"** — Face ID prompt на cold start. **Fix.** Биометрия только перед использованием. Push после первого успеха.

---

## 7. Single TLS session, multi-endpoint kitchen-sink proofs

Critical для rich proofs (Spotify-style таргеты, но Spotify dead).

**Mechanic.** TLSNotary supports множественные HTTP requests within one TLS session through `MpcTlsConfig::max_sent_data` / `max_recv_data`. Declare upfront. Selective reveal accepts multiple byte ranges из коробки.

**Example. Strava deep profile.**

```
1 TLS handshake → api.strava.com cert/SNI committed
GET /v3/athlete                      → identity (~200ms)
GET /v3/athlete/stats?id=<id>        → lifetime totals (~250ms)
GET /v3/athlete/activities?...       → 30 recent activities (~300ms)
GET /v3/athlete/zones                → HR zones (~200ms)
TLS close. Transcript ~20 KB.
↓
ONE Attestation. Merkle root over whole transcript.
Selective reveal by byte ranges. Redact 4× Authorization headers.
```

**Time.** ~2-3 с in proxy mode for ~20 KB transcript.

**Key insight.** Rich proofs не more expensive than simple proofs architecturally. Same one TLS session, same one Face ID on repeat. Only change. `max_recv_data` в prover config + number of reveal map entries. UX differs только в loading state (multi-stage instead of single) + success state structure.

### Cross-platform composition (Size 3)

"I am serious dev" = `f(github.contributions, stackoverflow.reputation, leetcode.rating)`. Каждая платформа = отдельный proof. Composition computed на стороне REP via Proof Graph Runtime **без новой минтинг-сессии**. **Это compounding moment графа.**

---

## 8. Open questions

1. **TLS 1.3 support в shipped TLSNotary build.** Public material pins TLS 1.2 (`TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256`). Many endpoints TLS-1.3-only. Verify against running prover before commit to each target.

2. **Cookie durability under replay.** UA-pinning / IP heuristics / device fingerprint / sliding rotation / CSRF tokens. Тестить per target. If cookie rejected → fall back на MPC mode (user IP).

3. **DPoP / mTLS exposure per target.** Confirmed rare in consumer APIs, mandatory в FAPI 2.0 / open banking / SMART-on-FHIR / Bluesky atproto. For financial / health / Bluesky fact — budget for in-proof DPoP signing or different approach. Not в Tier-1.

4. **Spotify-style API erosion.** Feb-2026 removal of `product`/`country` shows platforms actively stripping fields. Build OAuth→cookie auto-fallback per target.

5. **Anti-goal compliance для QR / remote-auth.** Don't lift session token silently. Explicit consent UI + scoped-to-single-proof token usage + client-side discard.

6. **Server-side credential custody.** Any architecture where REP holds user's cookie/token server-side (vs on-device) is privacy red flag. **On-device extension model = privacy-preferred default.**

7. **TestFlight AASA delays.** До 15 минут на AASA fetch ([Apple Forums #108339](https://developer.apple.com/forums/thread/108339)). Production install (App Store) не имеет.

---

## 9. Sources used (primary)

### TLSNotary
- [tlsnotary/tlsn source](https://github.com/tlsnotary/tlsn) (cloned, examples built locally)
- [proxy-mode blog 2026-04-22](https://tlsnotary.org/blog/2026/04/22/proxy-mode/)
- [benchmark post 2026-05-10](https://tlsnotary.org/blog/2026/05/10/blog-proxy-mode/)
- [extension docs](https://tlsnotary.org/docs/extension/)
- [Wasmtime iOS issue #5754](https://github.com/bytecodealliance/wasmtime/issues/5754)

### Reclaim
- [reclaim-inapp-ios-sdk](https://github.com/reclaimprotocol/reclaim-inapp-ios-sdk)
- [security FAQ](https://blog.reclaimprotocol.org/posts/security-faq)
- [zkTLS AI blog](https://blog.reclaimprotocol.org/posts/zktls-ai)
- [Proxying Is Enough](https://blog.reclaimprotocol.org/posts/proxying-is-enough)

### Primus
- [docs.primuslabs.xyz](https://docs.primuslabs.xyz/data-verification/developer-hub/)

### Plaid Link
- [iOS docs](https://plaid.com/docs/link/ios/)
- [OAuth guide](https://plaid.com/docs/link/oauth/)
- [Best Practices via Fintegration](https://medium.com/@FintegrationFS/plaid-link-best-practices-ux-conversion-tips-that-reduce-drop-off-in-bank-linking-c3b5fddf8930)

### Stripe Identity
- [iOS docs](https://docs.stripe.com/identity/verify-identity-documents?platform=ios&type=new-integration)
- [stripe-ios GitHub](https://github.com/stripe/stripe-ios)

### Apple Wallet
- [Apple Pay in-app provisioning demo](https://applepaydemo.apple.com/in-app-provisioning)
- [Lithic Push Provisioning](https://docs.lithic.com/docs/push-provisioning)

### Privy / Web3Auth
- [Privy iOS SDK](https://github.com/privy-io/privy-ios)
- [Privy Expo passkey](https://docs.privy.io/guide/expo/authentication/passkey)

### iOS APIs
- [Apple ASWebAuthSession docs](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
- [Apple `prefersEphemeralWebBrowserSession`](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/prefersephemeralwebbrowsersession)
- [Apple HIG Sign in with Apple](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple)
- [Apple SecAccessControl docs](https://developer.apple.com/documentation/security/secaccesscontrol-h)
- [Okta history of mobile SSO](https://developer.okta.com/blog/2022/01/13/mobile-sso)

### Android APIs
- [Chrome Custom Tabs](https://developer.chrome.com/docs/android/custom-tabs/overview/)
- [Steamclock CCT writeup 2025-05](https://steamclock.com/blog/2025/05/android-chrome-custom-tabs/)
- [Android Credential Manager](https://developer.android.com/identity/sign-in/credential-manager)

### Passkeys
- [FIDO Passkey Index 2025](https://fidoalliance.org/passkey-index-2025/)
- [Corbado conditional UI](https://www.corbado.com/blog/webauthn-conditional-ui-passkeys-autofill)
- [Yubico iOS WebAuthn autofill](https://developers.yubico.com/Mobile_Dev/WebAuthn/IOS/Authenticate_with_Autofill_and_Passkeys.html)
- [Corbado iOS 18 passkeys](https://www.corbado.com/blog/ios-18-passkeys-automatic-passkey-upgrades)
- [W3C webauthn#1862](https://github.com/w3c/webauthn/issues/1862)

### Targets
- [GitHub OAuth refresh docs](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/refreshing-user-access-tokens)
- [Spotify Feb 2026 changelog](https://developer.spotify.com/documentation/web-api/references/changes/february-2026)
- [Strava API reference](https://developers.strava.com/docs/reference/)
- [Duolingo unofficial API](https://tschuy.com/duolingo/api/data.html)
- [Codeforces apiHelp](https://codeforces.com/apiHelp/methods)
- [Anthropic Admin cost_report](https://platform.claude.com/docs/en/api/admin/cost_report)

### Universal Links
- [Apple Forums TestFlight AASA delay #108339](https://developer.apple.com/forums/thread/108339)
- [Bugfender debugging guide](https://bugfender.com/blog/ios-universal-links/)
- [Apple TN3155 Debugging universal links](https://developer.apple.com/documentation/technotes/tn3155-debugging-universal-links)

### Other
- [Google One Tap guide](https://securityboulevard.com/2025/09/the-complete-guide-to-google-one-tap-login-everything-developers-need-to-know/)
- [RFC 8252 OAuth 2.0 для Native Apps](https://www.rfc-editor.org/rfc/rfc8252.html)
- [RFC 7636 PKCE](https://datatracker.ietf.org/doc/html/rfc7636)
- [RFC 9449 DPoP](https://datatracker.ietf.org/doc/html/rfc9449)
- [Clerk OTP vs Magic Link via Scalekit](https://www.scalekit.com/blog/otp-vs-magic-links-passwordless-authentication)
- [Nielsen Norman response times](https://www.nngroup.com/articles/response-times-3-important-limits/)
