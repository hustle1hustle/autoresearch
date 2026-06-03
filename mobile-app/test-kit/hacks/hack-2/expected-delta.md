# Hack 2 — Expected Delta

## Источник прогноза

`../../mobile-ux-deep-research.md` §1 Hack 2:

> **Trick:** After the first GitHub proof, persist the OAuth refresh token in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` + `SecAccessControl` set to `.biometryCurrentSet`. On a second proof attempt, the entire OAuth dance is replaced by **Face ID → refresh-grant → notarize**.
>
> **Savings:** **2 taps → 1 tap** and **~7 s → ~3–4 s** for repeat proofs.

Источник для GitHub refresh policy. [GitHub OAuth refresh docs](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/refreshing-user-access-tokens). 8-hour access, 6-month refresh, rotated on use.

## Predicted deltas

| Scenario | Stock baseline | With Hack 2 | Delta (taps) | Delta (s) |
|---|---|---|---|---|
| warm-returning × GitHub | 2-3 taps / 5-10 s | 1 tap / 3-4 s | -1 to -2 taps | -2 to -6 s |
| warm-first × GitHub | n/a (нет cached token) | n/a | 0 | 0 |
| cold × GitHub | n/a | n/a | 0 | 0 |

**Important.** Hack 2 применим ТОЛЬКО к **повторам** же того proof'а. Первый proof остаётся warm-first. Hack 2 — это про **compounding на repeat use**, что критично для habit formation (см. `../../ROUTING.md` § "Why this matters").

## Где Hack 2 НЕ помогает

1. **GitHub OAuth app не настроен на refresh tokens.** Тогда нет refresh_token чтобы сохранить. Hack 2 неимплементируем.
2. **Targets без OAuth (Codeforces, StackOverflow public).** Нет токена → ничего сохранять. Hack 2 не применим. Эти таргеты имеют свои pattern'ы (binding via nonce).
3. **Cookie-path таргеты (Duolingo, LeetCode).** Hack 2 модифицирован. сохраняется не refresh_token, а cookie set. Но cookies часто sliding-rotation'ятся, и rememberance может не работать. Test on real targets, см. `../../open-questions.md` Q5.

## Где Hack 2 помогает БОЛЬШЕ

1. **Когда юзер re-prove'ит часто** (например ежедневно для streak'ов). Каждый раз 1 тап ≈ 3 секунды. Massive cumulative win.
2. **Когда сочетается с Hack 6.** Face ID анимация ~500 мс + notarize ~1.5 с проходят параллельно. Subjective perception = "тап → success" без визибл loading.

## Что сделать если delta меньше

- ✅ Проверь что refresh-grant действительно faster чем full OAuth. У некоторых OAuth providers refresh-grant сам по себе медленный
- ✅ Может быть Face ID prompt сам по себе медленно (slow Touch ID на старых девайсах)
- ✅ Hack 2 без Hack 6 = виден loading после Face ID. Скучный UX даже если быстрый

## Что сделать если delta больше

- 🎉 Если Hack 2 даёт ~2 секунды economy — отлично, документируй
- 🤔 Если > 5 секунд — подозрительно, проверь что stock baseline корректно меряется

## Cumulative metric. "1-tap rate"

Дополнительная метрика которую стоит трекать для Hack 2:

```
1-tap-rate = # proof attempts that finished in exactly 1 user tap
              / # total proof attempts for warm-returning юзеров
```

**Target.** ≥ 80% после первого proof'а. Меньше = либо Hack 2 ломается (recovery triggered), либо refresh_token часто revoked'ит.

## How this stacks

- **Hack 2 + Hack 6 = magic.** Pre-warm WebSocket (Hack 1) → refresh-grant фоном пока Face ID анимация → notarize пока iOS возвращает state. ВСЁ скрыто. T_perceived ≈ T_faceID_animation (~0.5 с).
- **Hack 2 alone (без Hack 6).** Виден loading после Face ID. Total visible ~3-4 с. Хорошо но не magic.

## Сравнение с альтернативами

| Approach | Taps | Seconds | Security |
|---|---|---|---|
| Stock TLSN (no caching) | 2-3 | 7 | OAuth каждый раз |
| Cache access_token in UserDefaults | 1 | 2 | ⚠️ insecure, любая аппка с file access |
| Cache refresh_token in Keychain (no biometry) | 1 | 2 | ⚠️ ok если unlocked, но shared physical access leak |
| **Hack 2. Keychain + .biometryCurrentSet** | 1 | 3-4 | ✅ user presence required, re-enroll invalidates |
| Refresh token in Secure Enclave (HSM-bound) | 1 | 3-4 | ✅✅ hardware-bound, but more complex API |

Hack 2 это правильный balance. достаточно secure для consumer use case, достаточно simple для шипания.

## Cite

- [GitHub OAuth refresh docs](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/refreshing-user-access-tokens) — refresh token policy
- [Apple SecAccessControl docs](https://developer.apple.com/documentation/security/secaccesscontrol-h) — biometry-bound items
- `../../mobile-ux-deep-research.md` §1 Hack 2 — predicted savings
- Apple Wallet add-card UX (`../../mobile-ux-deep-research.md` §3) — analogous pattern для credential caching
