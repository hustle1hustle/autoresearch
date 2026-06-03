# Hack 4 — Universal Link Auto-Return. Test Procedure

## Setup

1. Имплементируй AASA + entitlement (iOS) и assetlinks.json + autoVerify (Android) per `implementation-notes.md`
2. Verify AASA fetched. iOS Settings → Developer → enable Associated Domain Development → "applinks:rep.xyz?mode=developer"
3. Verify App Links. `adb shell pm get-app-links com.rep.app` → должно показать "verified"
4. Test host-shell установлен через TestFlight (не Xcode direct) для production-like behavior

## Measurement points

- **T_oauth_complete.** GitHub OAuth flow finished (user tapped Authorize)
- **T_redirect_to_https.** Browser navigated к `https://rep.xyz/oauth/github/callback`
- **T_host_shell_open.** Host-shell came to foreground via Universal Link
- **T_handler_called.** Host-shell `.onOpenURL` / `OAuthCallbackActivity` triggered
- **T_resume_state.** Host-shell resumed proof-in-flight state

## Test variants

### Variant A. Happy path. iOS production install

```
1. Install host-shell через App Store / TestFlight (let AASA fetch settle)
2. Wait 15 минут чтобы AASA точно fetched
3. Run warm-first GitHub flow
4. После "Authorize REP" tap
5. Observe: Safari ASWebAuthSession sheet collapses
6. Observe: Host-shell foreground автоматически
7. Observe: Notarize-in-flight state визибл (с loading стейджами)
```

**Hypothesis.** T_host_shell_open - T_oauth_complete < 1 секунда. Юзер видит smooth animation.

### Variant B. Custom scheme baseline (control)

Если у тебя есть build стого TLSN с custom scheme — прогон тот же flow.

**Hypothesis.** Юзер видит callback URL странице открытой в Safari, host-shell не открылся автоматически, юзер должен manually swipe-back / тапать "Open in REP". +5-10 секунд + drop-off risk.

### Variant C. TestFlight AASA delay reproduce

```
1. Uninstall host-shell
2. Reinstall через TestFlight
3. СРАЗУ (без 15 мин wait) попробовать OAuth flow
4. Observe: Universal Link может НЕ маршрутизировать
5. Observe: fallback web page показывается, юзер тапает "Open in REP"
6. Подожди 15 минут
7. Попробовать снова → теперь работает auto
```

**Hypothesis.** AASA fetch delay ~5-15 минут. Fallback web page gracefully handles. Production-mature install (через App Store) не имеет этой проблемы.

### Variant D. Android

```
1. Install host-shell через release build (signed properly)
2. Verify: adb shell pm get-app-links com.rep.app → verified
3. Run OAuth flow
4. Observe: Custom Tab collapses, host-shell foreground
5. Observe: OAuthCallbackActivity intent received, route to notarize
```

**Hypothesis.** Behavior симметричен iOS. Если "rejected" а не "verified" — assetlinks.json broken.

### Variant E. Recovery. AASA broken

Intentionally break AASA file (typo в bundle ID или missing component):

```
1. Update AASA с wrong appID
2. Reinstall host-shell
3. Run OAuth flow
4. Universal Link не маршрутизирует
5. Browser остаётся открытым на callback URL
```

**Hypothesis.** Юзер manually должен вернуться. Если ты implement'нул fallback web page — она показывает "Open in REP" deep-link. Если нет — юзер abandons.

## Output. Заполни в comparison/template.csv column `hack-4`

| Metric | warm-first × github |
|---|---|
| Universal Link auto-return rate | __ / 10 |
| Median T_host_shell_open - T_oauth_complete (ms) | __ |
| App-switches (visible) | __ |
| Manual swipe-back required? | YES/NO |
| Fallback web page triggered (TestFlight delay)? | __ / 10 |
| Drop-off after OAuth complete | __ % |
| Notes | __ |

## Sanity checks

1. **AASA actually fetched.** iOS. `swcutil show` в Terminal (требует macOS). Покажет registered associated domains and their fetch status.
2. **App Links verified.** Android. `adb shell pm get-app-links` output должно содержать `verified`.
3. **HTTPS-only callback.** Если в OAuth setup ты указал `http://` без s — AASA не работает.
4. **Path prefix matches.** Если AASA содержит `/oauth/github/callback*` но OAuth registered callback `https://rep.xyz/auth/github` — не маршрутизирует. Match paths exactly.
5. **Universal Link не работает если open from same domain.** Если юзер на rep.xyz tap'ает ссылку которая идёт на rep.xyz — iOS оставит в Safari (это known iOS behavior). Не баг.

## Pass/fail criteria

✅ **PASS** если:
- Variant A. Auto-return rate > 95%, median < 1с от OAuth complete до host-shell foreground
- Variant D. Android симметричный
- Variant E. Graceful fallback (либо works, либо web page показывает deep-link button)

❌ **FAIL** если:
- Auto-return rate < 90% (что-то не настроено)
- Manual swipe-back required (custom scheme used, не Universal Link)
- Host-shell crashes on callback URL
- Multi-second delay между OAuth done и host-shell open
