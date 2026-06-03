# Hack 3 — Expected Delta

## Источник

`../../mobile-ux-deep-research.md` §1 Hack 3:

> **Trick:** Before invoking `ASWebAuthenticationSession`, show a one-screen explainer.
>
> **Savings:** **+15–25 percentage points** of conversion through the system sheet, vs. surprising the user with it cold. Hard number is industry-talk so flagged `[ASSUMPTION + source: Okta + Plaid Link Best Practices]`.

## Predicted delta

| Metric | Stock (no pre-sheet) | With Hack 3 | Delta |
|---|---|---|---|
| iOS system_sheet_continue_rate | ~70-75% | ~85-95% | +15-25 п.п. |
| Overall warm-first completion rate | ~70% | ~85-90% | +15-20 п.п. |
| Android system_sheet_continue_rate | ~95% (CCT silent) | ~95% | ~0 п.п. |

**Note.** Tap count и seconds slightly INCREASE с Hack 3 (один доп тап + ~2 секунды читать). Но conversion rate растёт significantly. Net business value positive.

## Per-platform notes

| Platform | iOS impact | Android impact | Why |
|---|---|---|---|
| GitHub | ✅ large | ⚠️ minimal | OAuth handoff scary без pre-sheet |
| Strava | ⚠️ medium | ⚠️ minimal | Strava app-switch (если app installed) уже понятен юзеру |
| Duolingo | ✅ large | ⚠️ minimal | Cookie-path = web sheet scary |
| Codeforces | ❌ n/a | ❌ n/a | Нет auth flow |
| StackOverflow | ⚠️ medium | ⚠️ minimal | Похож на GitHub |
| LeetCode | ✅ large | ⚠️ minimal | Cookie-path |
| Anthropic | ❌ n/a | ❌ n/a | Admin key paste, не OAuth |

Pre-sheet применим к OAuth и cookie-reuse путям. Для public APIs (Codeforces) и admin-key путей (Anthropic) — не нужен.

## Где Hack 3 НЕ помогает

1. **Когда юзер уже видел системный шит раньше.** Returning users не пугаются sheet'а, и pre-sheet добавит friction (если ты неправильно сохраняешь флаг).
2. **На Android.** CCT шарит cookies тихо. Нет scary sheet'а который надо подготовить.
3. **Если pre-sheet copy generic.** "Tap Continue to continue" не помогает. Хуже того, юзер не доверяет.

## Где Hack 3 помогает БОЛЬШЕ ожидаемого

1. **Если pre-sheet связан с показом "what we'll share"** — юзер видит конкретно. username + contribution count. Меньше abstract страха.
2. **Если включает privacy reassurance "password never leaves GitHub"** — этот короткий phrase бьёт по основному страху пользователя.

## Метрика что мерять прежде всего

**Primary.** `system_sheet_continue_rate` = continues / shown. Должна быть > 80% с Hack 3.

**Secondary.** `pre_sheet_continue_rate` = pre-sheet continues / pre-sheet shown. Должна быть > 90%. Если < 90% — твой pre-sheet copy ломает trust.

**Tertiary.** `warm_first_completion_rate` = success / cta_taps. Должна расти на 15+ п.п. vs baseline.

## What this stacks with

- **Hack 1** ортогонален. WebSocket pre-warm идёт фоном пока юзер читает pre-sheet. 2-3 секунды на read = достаточно для full WebSocket open + PKCE gen.
- **Hack 4** prerequisite для honest measurement. Если Universal Link auto-return не работает, юзер vermeintlich завершил flow но ушёл в Safari. Conversion broken независимо от Hack 3.
- **Hack 6** ортогонален. Notarize-in-animation после OAuth.

## Что сделать если delta меньше

- ✅ Check copy. Generic copy не работает. Должно быть platform-specific и concrete.
- ✅ Check pre-sheet visual hierarchy. Continue button visible? Cancel doesn't overshadow Continue?
- ✅ Check timing. Если pre-sheet появляется WHILE iOS sheet shows simultaneously — broken UX. Pre-sheet должен полностью dismissal before ASWebAuthSession.start()
- ✅ Real-user N. С N=10 ты не различишь 75% от 85%. Нужен N≥50.

## Что сделать если delta больше

- 🎉 Скорее всего твой copy особенно good. Запиши точное wording в `../../open-questions.md` New findings для использования в других платформах.

## Cite

- [Okta history of mobile SSO](https://developer.okta.com/blog/2022/01/13/mobile-sso) — "intentionally scary" sheet observation
- [Plaid Link Best Practices](https://medium.com/@FintegrationFS/plaid-link-best-practices-ux-conversion-tips-that-reduce-drop-off-in-bank-linking-c3b5fddf8930) — explainer-before-system-action pattern
- [Apple HIG on Sign in with Apple](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple) — explain-before-action recommendation
- `../../mobile-ux-deep-research.md` §1 Hack 3 — predicted +15-25 п.п. conversion
