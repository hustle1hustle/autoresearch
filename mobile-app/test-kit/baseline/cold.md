# Baseline. Cold. Stock TLSN Mobile Build

**Сценарий.** Юзер впервые минтит GitHub proof, И он НЕ залогинен в GitHub нигде на этом девайсе. Cold cookie state.

**Target metric** (из `../mobile-ux-deep-research.md`). **4-5 тапов / ≤ 30 с total**, все хаки активны.

**Stock TLSN expectation.** 7-10+ тапов / ~30-60 с. Включая ввод email / пароля и 2FA если включена.

---

## Pre-conditions

- Stock TLSN build установлен СВЕЖЕ (как в warm-first)
- **GitHub.com НЕ залогинен** в Safari (clear cookies) и НЕТ нативной GitHub app залогиненной
  - iOS. Settings → Safari → Clear History and Website Data
  - Android. Chrome → Settings → Privacy → Clear browsing data
- Для теста с 2FA готовь Authenticator app (Google Authenticator / Authy) или GitHub mobile app для push-2FA
- Wi-Fi residential или 5G good signal
- ⚠️ ВНИМАНИЕ. Используй TEST GitHub account, не production. Cold flow требует ввод credentials.

## Test procedure

### Step 0. Cold app launch

```
1. Установи / переустанови host-shell
2. Tap app icon
   ┌─── STOPWATCH START (T_start) ───┐
3. Дождись first interactive frame
```

### Step 1. Onboarding

Как в warm-first. Прокликай до main screen, замеряй tap count.

### Step 2. Trigger first GitHub proof

```
4. Tap "Add GitHub" / "Connect GitHub"
```

### Step 3. OAuth handoff (cold path)

```
5. ASWebAuthSession iOS sheet → Continue
   (или CCT Android — без sheet)
6. Safari открывается. cold cookie → GitHub login page (НЕ consent)
```

### Step 4. Login form

Это самая медленная часть cold пути:

```
7. Tap username/email field
   - iOS. iCloud Keychain может предложить creds через AutoFill — если есть, тап и Face ID
   - Без autofill. ручной ввод
8. Tap password field
   - Та же autofill story
9. Tap "Sign in"
   T_login_form = (между tap 7 и tap 9)
```

**Что замеряешь.**
- T_login_form
- iCloud Keychain autofill сработал? (Это важный delta. с keychain ~3-5 с, без ~15-25 с)
- Сколько раз юзер промахнулся (capturing typos / retries)
- Если password забыт. ушёл в reset flow → abandon

### Step 5. 2FA если включена

```
10. GitHub шлёт 2FA challenge
    - TOTP. открой Authenticator, скопируй код, вернись, paste
    - WebAuthn (passkey). Face ID если passkey configured
    - SMS. подожди код, читай в notification, AutoFill or paste
11. Tap "Verify"
    T_2fa = duration of 2FA step
```

**Что замеряешь.**
- T_2fa
- Тип 2FA. TOTP / passkey / SMS / push
- Сколько app-switch'ей потребовалось для 2FA?
- Если push к GitHub mobile app. это app-switch + return

### Step 6. Consent screen

```
12. GitHub OAuth consent page → tap "Authorize REP"
```

### Step 7. Return + notarize

```
13. Universal Link / scheme return в host-shell
14. Notarize
    T_notarize_start
15. Success
    ┌─── STOPWATCH STOP (T_end) ───┐
```

## What counts as tap

См. `warm-returning.md`. ДОПОЛНИТЕЛЬНО для cold:

- ✓ Tap на username field (для focus) считается
- ✓ Tap на password field считается  
- ✓ Каждое нажатие на цифру 2FA кода считается? **НЕТ** — 2FA-code typing = ОДИН conceptual step. Считай tap = 1 за весь TOTP-entry, измеряй T_2fa отдельно
- ✓ Если AutoFill suggestion появилась и юзер тапнул её — это 1 tap (но T_login_form сильно меньше)

## What counts as abandon

См. `warm-returning.md`. ДОПОЛНИТЕЛЬНО:

- "Forgot password" tap → abandon (юзер уходит в password reset flow, это другой scenario)
- "Need help signing in" tap → abandon

## Output. Заполни в comparison/template.csv row `cold × github`

| Metric | Value |
|---|---|
| Taps (total) | __ |
| Seconds (T_total) | __ |
| Seconds (T_login_form only) | __ |
| Seconds (T_2fa only) | __ |
| Seconds (T_notarize only) | __ |
| App-switches | __ |
| Consent screens | __ |
| iCloud Keychain autofill triggered? | YES/NO |
| 2FA type | TOTP/SMS/passkey/push/none |
| 2FA app-switch required? | YES/NO |
| Errors / retries | __ |
| Success rate over 10 attempts | __ / 10 |
| Notes | __ |

## Cold-specific anti-patterns to watch

- **"Lost in inbox"** — НЕ должно возникнуть если юзер использует пароль. Но если builds offers "Email me a magic link" — это anti-goal. Зафиксируй.
- **"Permission requested before purpose"** — если host-shell спрашивает Face ID / Touch ID ДО завершения OAuth, это anti-pattern. Биометрия запрашивается ТОЛЬКО когда есть refresh_token чтобы сохранить.
- **2FA flow ломается?** Если 2FA app-switch теряет state в host-shell (юзер возвращается на cold start screen) — это критический баг и должен быть в open-questions.

## Common stock-TLSN observations

1. **Cold с keychain autofill** — ~15-20 с total
2. **Cold без autofill** — ~30-45 с total
3. **Cold + 2FA TOTP** — добавляет ~10-15 с
4. **Cold + восстановление пароля** — abandon, измеряй abandon rate отдельно

## Important. real numbers vs research target

Research target ≤ 30 с заявлен для cold-with-autofill. Cold-without-autofill реалистично ~45-60 с — research это эксплицитно не оговаривает. Если ты тестируешь без keychain autofill — отметь это в Notes и не обвиняй "хаки не работают", это просто более тяжёлая ветка пути.
