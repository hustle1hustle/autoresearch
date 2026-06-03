# Hack 2 — Refresh Token + Face ID. Test Procedure

## Setup

1. Имплементируй Hack 2 согласно `implementation-notes.md`
2. **Prerequisite.** Хакерь GitHub OAuth app настроен на refresh tokens (enable в OAuth App settings). Verify через `gh api /user/installations` или просто прогон первого proof'а — response должен содержать `refresh_token`
3. Host-shell установлен на тестовый девайс с настроенным Face ID

## Measurement points

- **T_tap.** Юзер тапнул "Prove again"
- **T_faceid_start.** Face ID system prompt появился
- **T_faceid_done.** Юзер успешно прошёл Face ID (success haptic)
- **T_refresh_done.** Access token получен через refresh-grant
- **T_notarize_done.** Proof готов
- **T_end.** Success state shown

## Test variants

### Variant A. Hot path. warm-returning после первого proof

**Pre-condition.** Юзер уже минтил GitHub proof, refresh_token в Keychain под Face ID.

```
1. Force-quit host-shell
2. Re-open
3. Navigate to "My proofs"
4. Tap "Prove again" on GitHub row    → T_tap
5. iOS Face ID prompt                  → T_faceid_start
6. User looks at phone                 → T_faceid_done
7. Background: refresh-grant fires    → T_refresh_done
8. Background: notarize fires
9. Success state                       → T_end
```

**Hypothesis.** T_total = T_end - T_tap ≤ 4 секунд. Tap count = 1.

### Variant B. Recovery. refresh_token revoked

**Pre-condition.** Refresh_token есть в Keychain, но юзер отозвал access в GitHub Settings.

```
1. ...тап + Face ID как в A...
2. Refresh-grant returns 400/401     → host-shell должен detect и fall back
3. Host-shell показывает recovery copy: "We need to reconnect GitHub. Quick — tap and Face ID."
4. Юзер тапает Reconnect             → full OAuth flow (как warm-first из baseline)
```

**Hypothesis.** Recovery воспринимается как 1 дополнительный тап + warm-first path. Total = warm-first time + ~2 сек на recovery copy display.

### Variant C. Face ID failure. user не прошёл биометрию

```
1. Тап → Face ID prompt
2. Face скрыто / отвернутый юзер / ошибка
3. iOS показывает retry, потом fallback на passcode
4. Если юзер cancel'нул — host-shell возвращает на main screen без error
5. Re-tap "Prove again" → новая попытка Face ID
```

**Hypothesis.** Host-shell корректно handle'ит cancel. **Не показывает error screen.** Просто возвращает на entry.

### Variant D. Re-enrollment Face ID

**Сложная для воспроизведения** но критичная. Tester:
1. Минтит proof успешно (refresh saved)
2. Settings → Face ID → Reset → Set up Face ID (re-enroll)
3. Возвращается в host-shell, тапает "Prove again"
4. Read-with-biometry fails (`errSecInteractionNotAllowed` или похожее)
5. Host-shell detects, удаляет Keychain entry, fall back на full OAuth

**Hypothesis.** Host-shell не падает. Юзер не видит scary error. Просто mini-onboarding "We need to set up GitHub again" → warm-first flow.

## Output. Заполни в comparison/template.csv column `hack-2`

| Metric | warm-returning × github |
|---|---|
| Median T_total (s) | __ |
| Median taps | __ |
| App-switches | __ |
| Face ID prompts | __ |
| Consent screens | __ |
| Recovery path triggered (out of 10 attempts) | __ |
| Recovery succeeded gracefully? | YES/NO |
| Re-enrollment handled gracefully? | YES/NO |
| Notes | __ |

Для warm-first и cold. Hack 2 неприменим напрямую (нет refresh_token до первого proof'а). Заполни `n/a`.

## Sanity checks

1. **Refresh token действительно сохраняется.** После warm-first успеха проверь Keychain. iOS Console.app → filter `com.rep.github.refresh` или Android Keystore inspection. Должен быть encrypted blob.
2. **Refresh token rotation.** Между двумя re-prove'ами Keychain entry изменилась? (GitHub ротирует refresh_token при каждом use.) Если ты не сохраняешь новый — следующий refresh failed.
3. **Face ID НЕ запрашивается при первом proof'е.** Face ID — только для READ из Keychain, который происходит только на repeat. На first warm-first прогон Face ID prompt НЕ должен появиться.
4. **`.biometryCurrentSet` работает.** В Variant D тест — после re-enrollment Keychain должен failed. Если работает после re-enroll'а — ты использовал `.biometryAny` (security hole).

## Pass/fail criteria

✅ **PASS** если:
- Variant A median T_total ≤ 4 s
- Variant A tap count = 1
- Variant B recovery работает gracefully
- Variant C cancel не ломает app
- Variant D re-enroll triggers full OAuth fallback

❌ **FAIL** если:
- T_total > 6 s (хак не работает)
- Face ID prompt висит дольше 10 секунд без timeout
- Host-shell crash'ится в любом variant'е
- Refresh token не rotated (следующий refresh fails)
