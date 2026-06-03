# Hack 5 — Conditional UI Passkey Probe. Test Procedure

## Setup

1. AASA включает webcredentials per `implementation-notes.md`
2. REP backend поддерживает passkey registration + assertion endpoints (`/api/passkey/register`, `/api/passkey/assert`, `/api/passkey/challenge`)
3. Тестовый юзер прошёл passkey registration хоть раз. Reg flow вне scope Hack 5 — это setup
4. iOS 17.5+ для test device, либо Android 14+

## Measurement points

- **T_screen_appear.** Login screen появился
- **T_probe_fired.** `performAutoFillAssistedRequests` вызван
- **T_chip_shown.** System autofill chip с passkey suggestion появился (если есть passkey)
- **T_user_select.** Юзер тапнул на passkey suggestion
- **T_faceid.** Face ID prompt
- **T_assertion_done.** Authentication assertion готова, отправлена backend
- **T_success.** REP session открыта

## Test variants

### Variant A. Has passkey on this device

```
1. Pre-condition. юзер уже registered passkey ранее, iCloud Keychain включен
2. Launch host-shell
3. Navigate to Login / REP entry
4. Tap email field (focus)
5. Observe: autofill chip "Sign in with Face ID" appears
   T_chip_shown
6. Tap chip
   T_user_select
7. iOS Face ID prompt → looks at phone
   T_faceid → T_assertion_done
8. REP session opened
   T_success
```

**Hypothesis.** T_total = T_success - T_user_select < 3 seconds. Total taps = 1 (chip tap).

### Variant B. No passkey on this device

```
1. Pre-condition. юзер never registered passkey ON THIS DEVICE
2. Launch host-shell, Navigate to Login
3. Tap email field
4. Observe: autofill chip может показать iCloud Keychain passwords (если есть) but NO passkey suggestion
5. Юзер typed email manually
6. Standard email/password flow
```

**Hypothesis.** Hack 5 silent failure. Юзер не видит passkey chip но также не видит no error. UX continues normally as if Hack 5 не существует.

### Variant C. Has passkey on OTHER device (iCloud Keychain synced)

```
1. Pre-condition. passkey registered на another device, iCloud Keychain sync
2. На THIS device — passkey доступен через iCloud
3. Launch, Navigate, tap email field
4. Observe: chip может показать passkey suggestion
5. Tap → Face ID
```

**Hypothesis.** Behavior same as Variant A. Cross-device passkey sync works через iCloud Keychain.

### Variant D. Conditional probe interrupted

```
1. Variant A setup
2. Tap email field → chip appears
3. Юзер тапает на password field instead (не на chip)
4. Behavior. chip disappears, ничего не происходит, юзер typing password
```

**Hypothesis.** No error. Conditional UI gracefully ignored when юзер chooses to ignore.

## Output. Заполни в comparison/template.csv column `hack-5`

| Metric | REP-self login |
|---|---|
| Probe success rate | __ / 10 |
| Median T_total (s, chip tap to success) | __ |
| Chip-show rate (when passkey present) | __ % |
| Chip-tap-rate (taps / shows) | __ % |
| Silent failure when no passkey (good!) | __ / 10 |
| Notes | __ |

Для GitHub / Strava / etc. Hack 5 не применим напрямую (OAuth не принимает WebAuthn). Заполни n/a в этих row'ах.

## Sanity checks

1. **`.textContentType(.username)`** установлен на email field. Без этого iOS не показывает passkey suggestions.
2. **AASA webcredentials section** существует. Без этого iOS не доверяет RP.
3. **Conditional UI это PROBE, не FORCE.** Если ты используешь `performRequests()` вместо `performAutoFillAssistedRequests()` — это модальный passkey prompt, не chip. Wrong implementation.
4. **RP не learn'ит availability silently.** Если ты в analytics emit'ишь "user has passkey: false" — ты нарушил privacy principle.

## Pass/fail criteria

✅ **PASS** если:
- Variant A. < 3 секунды от chip tap до success. Tap count = 1.
- Variant B. Silent failure (no error UI shown)
- Variant C. Cross-device sync works
- Variant D. Юзер cancelling not breaks

❌ **FAIL** если:
- Conditional UI приводит к full modal (wrong API)
- Silent failure показывает error UI
- Email field не surface passkey suggestion даже когда passkey exists

## Limitations to document

Если Hack 5 не помогает GitHub direct (потому что GitHub OAuth не accepts WebAuthn) — задокументируй это в test output. Hack 5 ВСЁ ЕЩЁ применим для:
- REP-self login (юзер залогинен в REP через passkey)
- Future cookie-path таргеты с passkey support
- Long-term, если GitHub когда-нибудь добавит passkey-as-OAuth-credential
