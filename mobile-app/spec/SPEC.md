# REP Mobile App — Spec (Opening + Onboarding Flow)

**Что строим.** Native mobile app (iOS-primary, Android parallel) который позиционируется как **каноническая мобильная zkTLS аппка**. Hero proof. "Prove your GitHub 2026 contributions". Target. warm returning user мintит proof в **≤ 2 тапа / ≤ 7 секунд**.

**Substrate.** TLSNotary (open-source, EF/PSE). Primus только secondary cross-reference. **Default mode = proxy** (~1-2 с). MPC fallback (~13 с) только для WAF'нутых таргетов.

**Связанные документы.** `RESEARCH.md` (полные обоснования всех решений), `assets/login-overview.html` (визуальная инфографика со сценариями и моковыми экранами).

---

## TL;DR. что отличает эту аппку от того что уже есть на рынке

1. **TLSNotary GA mobile app не существует.** Их iOS prover в экспериментальном `tlsnotary/ios-wasmtime`. Reclaim есть на мобайле но их UX opaque (всё в SDK чёрном ящике). Пустая категория.
2. **Warm returning user — 1 тап / ~3-4 сек.** Через стек хаков 1+2+6 (pre-warm WebSocket + refresh token в Keychain под Face ID + notarize прячется в OAuth-return animation).
3. **Multi-endpoint kitchen-sink proof'ы.** Одна TLS сессия с N запросами → один attestation. Богатые proof'ы не дороже простых.
4. **Onboarding UX is the moat.** Стена instant proof'ов формирует habit + graph depth до того как конкуренты успевают копировать. Это not just product feature, это thesis.

---

## Tech stack (locked decisions)

| Layer | iOS | Android |
|---|---|---|
| UI | SwiftUI (iOS 17+) | Jetpack Compose (Android 14+) |
| Auth handoff | `ASWebAuthenticationSession` (cookies share) или app-switch OAuth | Chrome Custom Tabs или app-switch OAuth |
| Deep link return | Universal Links + AASA | App Links + `assetlinks.json` |
| Biometric auth | `LocalAuthentication.LAContext` + Keychain `SecAccessControl(.biometryCurrentSet)` | `BiometricPrompt` + `EncryptedSharedPreferences` |
| Conditional passkey | `ASAuthorizationPlatformPublicKeyCredentialProvider.requestStyle=.conditional` (iOS 17.5+) | `CredentialManager` with `isConditional=true` (Android 14+) |
| TLS prover | TLSNotary mobile build (native bindings или WASM via Wasmtime) | TLSNotary mobile build |
| WebView for cookie capture | WKWebView + WKHTTPCookieStore | WebView + CookieManager |

**No React Native / Flutter.** Native paths преобладают по trust и performance. Прecisely в zkTLS performance критичен (notarize timing).

---

## Architecture

```
┌──────────────────────────────────────────────────┐
│ Host-Shell (наша app)                            │
│                                                   │
│  ┌──────────────┐    ┌────────────────────────┐  │
│  │ Onboarding   │    │ Connect-Target Screen  │  │
│  │ (REP-self    │    │  - pre-warm WebSocket  │  │
│  │  login)      │    │  - canOpenURL probes   │  │
│  └──────┬───────┘    │  - passkey probe       │  │
│         │            │  - pre-sheet explainer │  │
│         │            └──────┬─────────────────┘  │
│         │                   │                    │
│         ▼                   ▼                    │
│  ┌──────────────┐    ┌────────────────────────┐  │
│  │ Identity     │    │ OAuth Handoff          │  │
│  │ (REP user)   │    │ ASWebAuthSession /     │  │
│  └──────────────┘    │ App-Switch             │  │
│                      └──────┬─────────────────┘  │
│                             │                    │
│                             ▼                    │
│  ┌──────────────┐    ┌────────────────────────┐  │
│  │ Keychain     │◀──▶│ Token Manager          │  │
│  │ (refresh     │    │ - access/refresh       │  │
│  │  tokens      │    │ - PKCE                 │  │
│  │  biometry)   │    └──────┬─────────────────┘  │
│  └──────────────┘           │                    │
│                             ▼                    │
│                      ┌────────────────────────┐  │
│                      │ TLSN Prover            │  │
│                      │ (mobile build)         │  │
│                      └──────┬─────────────────┘  │
│                             │                    │
└─────────────────────────────┼────────────────────┘
                              ▼
                     ┌────────────────────┐
                     │ REP Verifier       │
                     │ (server-side)      │
                     └────────────────────┘
```

**Host-shell** — наша app. Wraps TLSN build, реализует все 6 хаков, отвечает за весь UX.

**TLSN Prover** — отдельный component, native bindings или WASM. **Не модифицируем.**

**REP Verifier** — наш сервер (выполняет роль notary). Отдельный deliverable вне scope mobile app.

---

## Mode routing (TLSNotary proxy vs MPC)

| Если data endpoint... | ...используй | Почему |
|---|---|---|
| Public/dev API (`api.github.com`, `api.strava.com`, `api.anthropic.com`) | **Proxy** | Token-rate-limited, не IP-flagged. ~1-2 с. Browser-clean. |
| Consumer surface за Cloudflare / Akamai / WAF (Amazon, Uber, Spotify internals) | **MPC** | Datacenter IP заблочат. MPC шлёт с user IP. ~13 с. |
| Device-attested endpoint (Revolut retail, hardened bank apps) | **Не строим** | Ни proxy ни MPC не помогают. Out of scope. |

**Default.** Proxy. Auto-flip на MPC если 403 / Cloudflare challenge от endpoint'а.

---

## Method routing (login flow)

```
on entry в connect-screen:
  // в фоне (silent, параллельно):
  A = canOpenURL("<target>-mobile://")    // app installed?
  B = passkey conditional UI probe         // REP passkey present?
  C = pre-warm WebSocket к verifier        // Hack 1

  // выбор primary CTA:
  if B сработал
      → 1 тап: Face ID → REP-self auth → если refresh token в Keychain → Hack 2 (1 тап total)
  else if A == true && факт в plain-bearer OAuth scope
      → app-switch OAuth + PKCE (2 тапа)
  else if факт в OAuth scope
      → ASWebAuthSession с pre-sheet (2-3 тапа)
  else if факт web-only
      → cookie path через WebView (Reclaim-style)
  else (последняя надежда)
      → SMS OTP

  NEVER:
      → magic-link, manual password
```

**Silent warm detection на iOS** (то что разрешено пост iOS 9):
- `canOpenURL` (declared в `LSApplicationQueriesSchemes`, cap 50 schemes)
- Universal Link installability (OS знает по AASA)
- Conditional UI passkey probe (privacy-preserving by W3C design)

**Что НЕ делаем.** Hidden WKWebView к таргету для проверки сессии (anti-goal violation).

---

## Hero flow. "Prove your GitHub" — screen-by-screen iOS spec

### Warm returning (1 тап / ~3-4 с)

```
┌─────────────────────────────────┐        ┌─────────────────────────────────┐
│  REP                          ⋯ │        │  REP                          ⋯ │
│                                  │        │                                  │
│   Your context                   │        │   ┌─────────────────────────┐   │
│   ─────────────────              │        │   │  Face ID                │   │
│   ✓ GitHub  octocat              │   →    │   │                         │   │
│              1,234 contributions │  tap   │   │  Use Face ID to refresh │   │
│              earlier today       │  row   │   │  GitHub access          │   │
│                                  │        │   │                         │   │
│   ┌────────────────────────┐     │        │   │  [Cancel]               │   │
│   │ + Prove again       ⌄ │     │        │   └─────────────────────────┘   │
│   └────────────────────────┘     │        │                                  │
│                                  │        │   (Hack 6: notarize runs        │
│   + Add platform                 │        │    in background, hidden under  │
└─────────────────────────────────┘        │    Face ID animation)            │
                                            └─────────────────────────────────┘
                                                              ↓
                                            ┌─────────────────────────────────┐
                                            │  REP                          ⋯ │
                                            │                                  │
                                            │      ✓                          │
                                            │   Proof minted                  │
                                            │   octocat · 1,247 contributions │
                                            │                                  │
                                            │   [Share]   [What was proved ⌄]│
                                            └─────────────────────────────────┘
```

**Tap count.** 1. **Total seconds.** ~3-4. **App-switches.** 0. **Consent screens.** 0.

### Warm first time (2-3 тапа / ~7-10 с)

```
1. REP entry → tap "Connect GitHub"
2. Pre-sheet (Hack 3): "We'll ask GitHub to share... Next iOS will ask permission..."
   → tap "Continue with GitHub"
3. iOS consent sheet: "App wants to use github.com to Sign In"
   → tap "Continue"
4. Safari opens GitHub OAuth (cookie warm → consent page, auto-skip login)
5. tap "Authorize REP"
6. Universal Link auto-return (Hack 4)
7. Notarize in flight (~1-2 с)
8. Save refresh_token to Keychain under .biometryCurrentSet (Hack 2 setup)
9. Success state shown
```

### Cold (4-5 тапов / ~20-30 с)

Same as warm-first, плюс GitHub login form (email + password, ~10-20 с) + опциональный 2FA (~5-15 с).

### Error / fallback паттерны

| Error | Recovery copy |
|---|---|
| User cancels OAuth | "Got it. You can connect GitHub later." |
| OAuth scope denied | "GitHub needs to share your contribution count for this. Want to try again?" |
| Universal Link не открыл app | Fallback web page показывает manual "Open in REP" deep-link (TestFlight-only, production не видит) |
| Cloudflare challenge | "GitHub is being cautious. Switching to the slower-but-stronger proof mode (~13s)…" |
| Proof failed mid-flight | "Connection dropped. Try again — we don't keep anything from the failed attempt." |
| Refresh token revoked | "We need to reconnect GitHub. Quick — tap and Face ID." |

---

## 6 хаков (как features для build)

### Hack 1. Pre-warm WebSocket on screen mount

**Что.** Открыть WebSocket к verifier и сгенерировать PKCE до тапа CTA.

**Как.** SwiftUI `.task` модификатор на `ConnectGitHubView`. Запускается при появлении view, до тапов.

**Экономия.** ~500-1000 мс perceived latency.

**Источник.** Plaid Link iOS `Plaid.create()` + `onLoad` callback pattern.

### Hack 2. Refresh token + Face ID

**Что.** Сохраняем OAuth refresh_token в Keychain под `.biometryCurrentSet`. На повторе Face ID → silent grant → notarize.

**Как.** iOS. `SecAccessControlCreateWithFlags(.biometryCurrentSet)` + `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Android. `EncryptedSharedPreferences` + `BiometricPrompt`.

**Экономия.** 2-3 тапа → 1 тап, ~7 с → ~3-4 с на повторах.

**Что breaks it.** GitHub refresh policy. access 8h, refresh 6 months. Re-enrollment Face ID инвалидирует item (это feature, fall back на full OAuth).

### Hack 3. Pre-sheet explainer (iOS only)

**Что.** Перед `ASWebAuthSession` показывает экран с copy "Сейчас iOS спросит... пароль остаётся у GitHub".

**Как.** SwiftUI sheet с `.presentationDetents([.medium])`. Один раз per platform. `@AppStorage("hasSeenGitHubPreSheet")` флаг.

**Экономия.** +15-25 п.п. conversion через iOS system sheet.

**Android.** Опционален. CCT шарит cookies silently, нет scary sheet.

**Источник.** Okta history of mobile SSO + Plaid Link Best Practices.

### Hack 4. Universal Link auto-return

**Что.** OAuth callback URL = Universal Link с AASA. iOS автоматически маршрутизирует back в host-shell.

**Как.**
- AASA в `https://rep.xyz/.well-known/apple-app-site-association`
- Entitlement `applinks:rep.xyz` в `Entitlements-Release.plist`
- `.onOpenURL { url in ... }` или `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)`
- ASWebAuthSession `callback: .https(host:path:)` (iOS 17.4+) ИЛИ `callbackURLScheme: nil`

**Экономия.** Убирает ~30% swipe-back drop-off.

**Что watch.** TestFlight AASA fetch delay до 15 минут. Production install (App Store) не имеет.

**Android.** App Links + `assetlinks.json` + `android:autoVerify="true"`. То же логически.

### Hack 5. Conditional UI passkey probe

**Что.** `mediation: "conditional"` фоном проверяет наличие passkey без UI. Если есть → autofill chip.

**Применимо.** REP-self login + cookie-path таргеты с passkey support.

**Не применимо.** GitHub OAuth direct flow (GitHub не accepts WebAuthn для OAuth token issuance).

**Как.** iOS. `ASAuthorizationPlatformPublicKeyCredentialProvider` + `performAutoFillAssistedRequests`. AASA включает `webcredentials:rep.xyz`.

**Экономия.** 3-5 с вход когда применимо. **Privacy-preserving.** RP не learn'ит availability.

### Hack 6. Notarize-in-animation

**Что.** Notarize (GraphQL + selective disclosure) запускается **параллельно** с iOS app-switch return animation. ~400 мс анимация прячет ~1-2 с notarize.

**Как.** В OAuth completion handler. `Task.detached(priority: .userInitiated) { ... }` для notarize + `withAnimation(.snappy(duration: 0.4)) { ... }` для view transition. Параллельно.

**Экономия.** Скрывает ~1-2 с notarize entirely для warm path. Юзер видит "тап → done".

**Что watch.** Timeout safety. Если notarize > 2 с — переключиться на stage progress UI (Connecting → Confirming → Sealing).

**Источник.** Plaid "callback ordering is not guaranteed" pattern + Nielsen Norman response time thresholds.

---

## Anti-goals. чего НЕ делаем

| Anti-pattern | Фикс |
|---|---|
| "Spinner without context" — `ProgressView()` без copy | Стадии через `✓ / ● / ○`. Никогда слова "Loading". |
| "Did it work?" — silent success | Явный success state с фактом. Optional local push notification. |
| "Lost in inbox" — magic-link | NEVER. Magic-link не primary/secondary. Только OTP-код. |
| "Where did I come from" — manual swipe back | Universal Link auto-return (Hack 4) mandatory. |
| "Scary system sheet" — iOS sheet в лоб | Pre-sheet objашнение (Hack 3) — показывается один раз. |
| "App-switch you can't trust" — WKWebView для чужих паролей | NEVER. ASWebAuthSession (URL visible) или нативный app-switch. |
| "Re-prove every time" — full OAuth каждый раз | Hack 2 — refresh token + Face ID на повторах. |
| "Branded sheet on third-party login" — тяжёлый REP-брендинг во время GitHub-пароля | Бренд таргета доминирует. REP subtle до success state. |
| "What was just proved" — green checkmark без раскрытия | Expandable "What was proved" card с request, revealed bytes, redacted bytes, нотариус, expiry. |
| "Permission before purpose" — Face ID prompt на cold start | Биометрия только перед использованием. Push только после первого успеха. |

---

## 30-day path

**Неделя 1.**
- GitHub OAuth app, PKCE + app-switch
- Verifier service (отдельный repo), allow-list `api.github.com`, signing key
- Hack 1 (pre-warm WebSocket), Hack 3 (pre-sheet), Hack 4 (Universal Links), Hack 6 (notarize-in-animation)
- Базовый iOS prototype с warm-first сценарием

**Неделя 2.**
- Hack 2 (refresh token + Face ID). Warm returning путь.
- "What was proved" expandable card в success state
- Share artifact v1 — hosted verifier page `https://rep.xyz/p/<id>`
- Cold путь с error/fallback handling

**Неделя 3.**
- Android port. Custom Tabs + CredentialManager
- Strava как second target. OAuth `activity:read`, multi-endpoint kitchen-sink
- Hack 5 (conditional UI passkey probe) для REP-self login

**Неделя 4.**
- Instrumentation. event-spec из assets
- 3 A/B теста setup. pre-sheet, notarize-in-animation perceived survey, Universal Link return rate
- Internal QA с реальной командой как cold/warm/warm-returning юзерами
- Подготовка к открытой beta

---

## Tier-1 launch set (JSON-only)

| Платформа | Mode | Auth | Endpoint |
|---|---|---|---|
| **GitHub** ⭐ HERO | Proxy | OAuth `read:user` app-switch | `POST /graphql` (GraphQL batched fields) |
| Strava | Proxy | OAuth `activity:read` deep-link | `/v3/athlete` + stats + activities + zones (multi-endpoint) |
| Duolingo | Proxy (conditional) | Cookie reuse (WKWebView) | `/2017-06-30/users/{id}?fields=streak,totalXp,...` |
| Codeforces | Proxy | None (public) + nonce-binding | `/api/user.info` + rating + status |
| StackOverflow | Proxy | OAuth для `/me` | `/2.3/me` + answers + tags |
| LeetCode | Proxy (conditional) | Cookie reuse | `POST /graphql` (matchedUser + ranking) |
| Anthropic | Proxy | Admin key paste | `/v1/organizations/cost_report` + usage |

**Spotify tier proof мёртв** post-Feb-2026 (`product` field удалён). Не в launch set.

---

## Share artifact (v1)

**Hosted deep link** `https://rep.xyz/p/<id>`. Recipient видит claim summary, нотариев public key, "Verify cryptographically" button что делает signature check в browser. **Cost.** REP хостит page (cheap. static + minimal API). v2 = portable `.rep` файл, v3 = iOS Wallet pass.

---

## Open questions для team

1. **TLS 1.3 support в shipped TLSNotary build.** Public материал часто пинит TLS 1.2. Многие endpoints 1.3-only. Verify per target.
2. **Cookie durability under replay** для cookie-path таргетов (Duolingo, LeetCode). UA/IP pinning может ломать replay из fresh TLS session. Test per target.
3. **DPoP / mTLS exposure.** Bank / health / Bluesky APIs часто bound tokens. Bearer-replay не работает. Не в Tier-1, но flag.
4. **Spotify-style API erosion.** OAuth scope removals возможны. Build OAuth→cookie auto-fallback.
5. **Anti-goal compliance для QR / remote-auth.** Никогда не лифтить session token tih silently. Explicit consent + scoped-to-single-proof token.

См. полные ответы в `RESEARCH.md` § "Open questions" + `assets/login-overview.html` § "Sources to start from".

---

## Measurement targets (для validation pre-ship)

| Metric | Target |
|---|---|
| `tap_count_warm_returning` | 1 |
| `time_to_proof_p50_warm_returning` | ≤ 4 s |
| `time_to_proof_p50_warm_first` | ≤ 7 s |
| `time_to_proof_p50_cold` | ≤ 30 s |
| `presheet_continue_rate` | > 90% |
| `system_sheet_continue_rate` | > 80% |
| `oauth_consent_approval_rate` | > 95% first run |
| `universal_link_return_rate` | > 98% |
| `notarize_p50` | < 2 s |
| `notarize_p95` | < 5 s (выше = MPC fallback) |
| `success_rate_per_target` | > 85% warm, > 60% cold |

Event spec и instrumentation snippets — в `RESEARCH.md` § Measurement или (если был отдельный test kit) в `assets/`.
