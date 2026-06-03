# Hack 4 — Expected Delta

## Источник

`../../mobile-ux-deep-research.md` §1 Hack 4:

> **Trick:** Configure REP's OAuth redirect URI as a Universal Link backed by Apple's `apple-app-site-association` (AASA) file at `https://rep.xyz/.well-known/apple-app-site-association`. After GitHub finishes OAuth, iOS routes the redirect into our app *automatically*, with the system-managed `ASWebAuthenticationSession` collapsing cleanly.
>
> **Savings:** prevents the "manual swipe-back" anti-pattern that costs ~3–8 s and ~30% drop-off when a user lands on a callback page they don't know how to leave.

## Predicted delta

| Metric | With custom scheme | With Hack 4 | Delta |
|---|---|---|---|
| OAuth complete → host-shell foreground (s) | 3-8 (manual swipe-back) | <1 (auto) | -3-7 s |
| Drop-off after OAuth complete (%) | ~30% | <5% | -25 п.п. |
| App-switches visible to user | 2 (browser → manual back → app) | 1 (browser collapses) | -1 |
| Universal Link auto-return rate | n/a | >95% (production install) | n/a |

**Important.** Без Hack 4 ты теряешь юзеров буквально на финальной миле — они прошли OAuth, тапнули Authorize, но не знают как вернуться в host-shell. Это самый болезненный drop-off потому что юзер уже сделал работу.

## Где Hack 4 НЕ помогает

1. **Если build вшит на custom URL scheme** в TLSN глубже чем host-shell может override. См. `../../open-questions.md` Q3.
2. **TestFlight first 15 минут.** AASA не fetched. Production install (App Store) не имеет этой проблемы.
3. **Private network testing.** Если AASA сервер за corporate VPN — Apple CDN не cache. Используй mode=developer.

## Где Hack 4 помогает БОЛЬШЕ

1. **На repeat OAuth flows.** Если юзер несколько раз re-prove'ит (например streak ежедневно), каждый раз без Hack 4 = manual swipe-back. С Hack 4 → invisible. Cumulative win большой.
2. **С Hack 6 stacked.** Notarize-in-animation требует чтобы возврат был seamless. Universal Link auto-return это enabler.

## Per-platform notes

Hack 4 универсальный per всем OAuth-target'ам. Должен работать одинаково на:
- GitHub (HTTPS redirect)
- Strava (HTTPS redirect через `/oauth/strava/callback`)
- StackOverflow (HTTPS redirect)
- Anthropic (no OAuth, не применим)

Для cookie-path таргетов (Duolingo, LeetCode) Universal Link не нужен. Cookie capture делается **inside** WKWebView или ASWebAuthSession без redirect к нашему домену.

## Что мерять прежде всего

**Primary.** `universalLinkReturn rate` = auto-returns / OAuth completes. > 95% means Hack 4 работает.

**Secondary.** `swipe-back-required rate` = manual swipes / OAuth completes. ≤ 5% with Hack 4.

**Tertiary.** Drop-off rate post-OAuth-complete. Сравни до и после Hack 4. Должно упасть на ~25 п.п. (sources reference).

## Что сделать если delta меньше ожидаемого

- ✅ Verify AASA fetched correctly via `swcutil show` (macOS Terminal)
- ✅ Verify entitlement in **Release** build (не только Debug)
- ✅ Verify path prefix в AASA matches actual OAuth callback URL exactly
- ✅ Test от App Store install (TestFlight) vs Xcode direct run. AASA delays different
- ✅ Test on iPhone vs iPad (Universal Links work both, but configuration sometimes differs)

## Что сделать если delta больше

- 🎉 Probably means stock baseline был ужасно broken. Document the exact user-pain you replaced

## Anti-pattern reminder

`../../mobile-ux-deep-research.md` §6 "Where did I come from?" — это ровно проблема Hack 4 фиксит. Запиши в `../../ANTI-PATTERNS-CHECKLIST.md` что host-shell с Hack 4 = ✓ для этого антипаттерна.

## Cite

- [Plaid Link iOS docs](https://plaid.com/docs/link/ios/) — "Plaid uses Universal Links… prevents arbitrary app interception"
- [Apple Developer Forums TestFlight AASA delay](https://developer.apple.com/forums/thread/108339) — known delay quirk
- [Bugfender iOS Universal Links debugging guide](https://bugfender.com/blog/ios-universal-links/) — debug techniques
- [Android App Links](https://developer.android.com/training/app-links) — Android equivalent
- `../../mobile-ux-deep-research.md` §1 Hack 4 — predicted savings
