# Hack 3 — Pre-sheet Explainer. Test Procedure

## Setup

1. Имплементируй Hack 3 в host-shell'е (см. `implementation-notes.md`)
2. Verify. флаг `hasSeenGitHubPreSheet` в UserDefaults / SharedPreferences начинает с false
3. Установка swежая (clear UserDefaults) для тестирования first-time path

## Measurement points

- **T_cta_tap.** "Connect GitHub" тапнут
- **T_presheet_shown.** Pre-sheet appears
- **T_presheet_continue.** Юзер тапнул Continue в pre-sheet
- **T_system_sheet_shown.** iOS ASWebAuthSession consent появился
- **T_system_sheet_continue.** Юзер тапнул Continue на iOS sheet
- **T_oauth_done.** OAuth flow закончился (universalLinkReturn)
- **T_end.** Success state

## Test variants

### Variant A. First-time iOS юзер (где Hack 3 важнее всего)

```
1. Clean UserDefaults state (delete app, reinstall)
2. Cold start
3. Navigate to ConnectGitHubView
4. Tap "Connect GitHub"           → T_cta_tap
5. Pre-sheet appears               → T_presheet_shown
6. Юзер читает 2-3 секунды
7. Tap "Continue with GitHub"      → T_presheet_continue
8. iOS consent sheet appears       → T_system_sheet_shown
9. Tap Continue                    → T_system_sheet_continue
10. ...OAuth + notarize...
11. Success                         → T_end
```

**Hypothesis.** T_system_sheet_continue / T_system_sheet_shown ratio (continue rate) > 80% across 10 attempts vs ~70% без pre-sheet.

### Variant B. Repeat iOS юзер

```
1. NOT clean state. сделано Hack 3 Variant A раньше
2. Force-quit + re-open
3. Navigate to ConnectGitHubView
4. Tap "Connect GitHub"            → T_cta_tap
5. NO pre-sheet (флаг = true)      → STRAIGHT to T_system_sheet_shown
6. ...OAuth + notarize...
```

**Hypothesis.** Pre-sheet НЕ появился, юзер сразу на iOS sheet. Конверсия system-sheet-continue высокая потому что юзер уже знаком.

### Variant C. Android (where Hack 3 less critical)

```
1. Clean state Android app data
2. Cold start
3. Navigate
4. Tap "Connect GitHub"
5. Pre-sheet (если ты делаешь его на Android тоже)
6. Continue → Chrome Custom Tab opens silently (no consent sheet)
7. ...OAuth...
```

**Hypothesis.** На Android pre-sheet не существенно меняет конверсию, потому что CCT тихо шарит cookies. Delta minimal.

### Variant D. Pre-sheet с cancel

```
1. Clean state
2. Tap Connect → Pre-sheet
3. Юзер тапает Cancel в pre-sheet
4. Возврат на main screen без error
5. Tap Connect снова → Pre-sheet снова появляется (флаг ещё false, потому что Continue не нажат)
```

**Hypothesis.** Cancel'ит без вреда. Re-tap снова показывает sheet до тех пор пока Continue не нажат хоть раз.

## Conversion measurement

Pre-sheet impact самое чёткое в **system_sheet_continue_rate**:

```
Без Hack 3:
  taps "Connect GitHub" = 100
  iOS sheet shown = 100
  Continue tapped = 73    → 73% continue rate

С Hack 3:
  taps "Connect GitHub" = 100
  Pre-sheet shown = 100
  Pre-sheet continue = 92
  iOS sheet shown = 92
  Continue tapped = 88    → 96% sheet continue rate
                          → но 88% overall (потому что 8 cancel'нули pre-sheet)
```

Net conversion. **88% с Hack 3 vs 73% без = +15 п.п.** Это и есть expected delta.

### Real conversion delta нужен бóльший sample

Conversion deltas requires N≥50 per group. С 10 attempts ты не получишь statsig number. Use estimates from Plaid Best Practices (~+15-25 п.п.) до того как соберёшь real data.

## Output. Заполни в comparison/template.csv column `hack-3`

| Metric | warm-first × github |
|---|---|
| Pre-sheet shown rate | __ / 10 |
| Pre-sheet continue rate (continue / shown) | __ / __ |
| iOS sheet continue rate (continue / shown) | __ / __ |
| Overall completion rate (cta tap → success) | __ / 10 |
| Median T_total (s) | __ |
| Median T_presheet_read (T_continue - T_shown) | __ |
| Notes | __ |

Для warm-returning. n/a (pre-sheet уже видели). Для cold. Hack 3 применяется, но other taps доминируют — заполни но не expect большого delta именно от Hack 3.

## Sanity checks

1. **Pre-sheet появляется ТОЛЬКО first time per platform.** На второй раз он НЕ должен появляться. Если появляется — ты не сохраняешь `hasSeenGitHubPreSheet`.
2. **Cancel work без error.** Если cancel ломает app — bug.
3. **Pre-sheet content matches platform.** GitHub pre-sheet говорит про GitHub, не про generic OAuth. Если ты используешь generic копию — пере-имплементируй.
4. **Pre-sheet detents правильные.** Должен быть medium, не fullscreen. Юзер должен видеть что под ним — это сохраняет context.

## Pass/fail criteria

✅ **PASS** если:
- Variant A. system_sheet_continue_rate > 80%
- Variant B. pre-sheet НЕ показывается (флаг работает)
- Variant C. Android — корректно работает (даже если minimal delta)
- Variant D. cancel не ломает

❌ **FAIL** если:
- Pre-sheet появляется на repeat (UserDefaults не сохраняется)
- Copy generic ("Tap Continue to continue")
- Pre-sheet модальный без cancel
- Cancel triggers error
