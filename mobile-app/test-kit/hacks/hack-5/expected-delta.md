# Hack 5 — Expected Delta

## Источник

`../../mobile-ux-deep-research.md` §1 Hack 5:

> **Trick:** On the entry screen, fire a `mediation: "conditional"` WebAuthn assertion in the background. If the user has a passkey for the target RP (or for REP itself), iOS surfaces it in the system autofill chip — one tap, Face ID, done.
>
> **Savings:** when applicable, **passkey login is 8.5 s vs 31.2 s for MFA (73% faster)** and **Microsoft's synced passkeys are ~3 s vs 69 s for passwords**

Источники timing. [FIDO Passkey Index 2025](https://fidoalliance.org/passkey-index-2025/).

## Predicted delta

**Когда применим (REP-self login + future cookie-path таргеты с passkey support):**

| Scenario | Without passkey | With Hack 5 | Delta |
|---|---|---|---|
| REP-self login (cold, new device) | 30+ s (email+code/OTP) | 3-5 s (chip + Face ID) | -25+ s |
| REP-self login (warm, returning) | 5-8 s | 3-5 s | -2-3 s |
| Duolingo login (если они add passkey) | 8-15 s (email+pwd) | 3-5 s | -5-10 s |

**Не применим к Tier-1 OAuth таргетам (GitHub, Strava, StackOverflow, Anthropic).** Их OAuth flow не принимает WebAuthn для token issuance. Прогон Hack 5 на этих платформах = `n/a` в matrix.

## Где Hack 5 НЕ помогает

1. **OAuth direct flow.** GitHub, Strava, StackOverflow OAuth токены issued через password / 2FA auth, не через passkey. Hack 5 не сокращает их flow.
2. **Юзер без passkey на устройстве.** Silent failure — это feature, но и delta = 0.
3. **iOS < 17.5 / Android < 14.** Conditional UI не поддерживается.
4. **iCloud Keychain выключен.** Passkey не sync'ится между устройствами юзера.

## Где Hack 5 помогает БОЛЬШЕ

1. **Многократные re-logins в REP.** Каждый раз сокращён до 3-5 секунд vs 30 с email-code.
2. **Cross-device sign-in.** Юзер switch'нул на iPad, его iCloud Keychain passkey работает. Без passkey ему нужно делать email-code заново.

## Реальный business impact в нашем контексте

В Tier-1 OAuth flow Hack 5 = 0. Hack 5 critically для:

1. **REP authentication itself.** Если REP требует sign-in перед первым proof'ом — Hack 5 сокращает up to 25 секунд cold start.
2. **Future-proofing.** Когда Duolingo / LeetCode / Spotify добавят passkey — мы автоматически выигрываем без переделок.

## Что мерять

**Primary.** `passkey_login_time` (chip tap → success). < 5 секунд = pass.

**Secondary.** `passkey_offer_rate` среди юзеров с passkey. > 90% = chip показывается.

**Tertiary.** `passkey_adoption_rate` среди новых юзеров. Это metric для onboarding flow ("Want to set up Face ID for next time?"), не direct measurement Hack 5.

## Что сделать если delta меньше

- ✅ Verify AASA `webcredentials` section
- ✅ Verify `.textContentType(.username)` на email field
- ✅ Verify `performAutoFillAssistedRequests`, не `performRequests`
- ✅ Test на iOS 17.5+ (раньше — не работает)

## Что сделать если delta больше

- 🎉 Document какой именно RP / setup даёт fastest passkey flow
- 🤔 Если delta > 30 с — probably сравниваешь с email-code flow что too slow baseline. Hack 5 sub-second vs sub-second comparisons hardest

## How this stacks

- **Hack 1-6** ortho к Hack 5. Они про OAuth flow, Hack 5 про passkey flow. Разные пути.

## Cite

- [FIDO Passkey Index 2025 PDF](https://fidoalliance.org/wp-content/uploads/2025/10/FIDO-Passkey-Index-October-2025.pdf) — 8.5 с passkey vs 31.2 с MFA
- [Corbado iOS 18 automatic passkey upgrades](https://www.corbado.com/blog/ios-18-passkeys-automatic-passkey-upgrades) — conditional UI deep dive
- [Yubico iOS WebAuthn autofill](https://developers.yubico.com/Mobile_Dev/WebAuthn/IOS/Authenticate_with_Autofill_and_Passkeys.html) — implementation reference
- [W3C webauthn#1862](https://github.com/w3c/webauthn/issues/1862) — privacy-preserving conditional mediation rationale
- `../../mobile-ux-deep-research.md` §1 Hack 5
