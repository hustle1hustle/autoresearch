# Baseline. Warm Returning. Stock TLSN Mobile Build

**Сценарий.** Юзер УЖЕ минтил GitHub proof в этом app'е раньше (на этом же девайсе). Хочет повторить (re-prove).

**Target metric** (research target из `../mobile-ux-deep-research.md` TL;DR). **1 тап / ≤ 7 с total**, при условии все хаки активны.

**Stock TLSN expectation** (without our hacks). 2-3 тапа / ~5-10 с. Минимально потому что TLSN сам по себе не запоминает state между minting'ами (no Hack 2).

---

## Pre-conditions

- Stock TLSN build установлен на тестовый девайс
- Юзер уже минтил GitHub proof хотя бы один раз
- Девайс залогинен в GitHub.com в Safari (или в нативной GitHub app если приложение установлено)
- Wi-Fi residential или 5G good signal
- Сетевой инструмент (Charles Proxy / mitmproxy / Wireshark mobile) опционально для подсчёта TLS handshake таймингов

## Test procedure

### Step 0. Reset to known state

```
1. Закрой TLSN host-shell полностью (force-quit)
2. НЕ удаляй app (Keychain entries должны сохраниться if any)
3. Открой app cold (нажми icon на home screen)
```

**Что замеряешь.** App launch → first interactive frame. Это T₀.

### Step 1. Open existing GitHub proof / re-prove flow

```
4. Тапни row с GitHub proof'ом (или эквивалент "My proofs" + GitHub)
   ┌─────── STOPWATCH START ────────┐
   T_start = T₀
```

**Что замеряешь.** Tap count здесь = 1 (это первый тап от idle screen).

### Step 2. TLSN re-mint trigger

Здесь варианты по build'у:
- **Variant A.** Есть кнопка "Prove again" / "Refresh" — тапни её. tap count++
- **Variant B.** Нужно пройти полный OAuth заново (нет re-mint flow в build'е) — записывай это как **Stock TLSN limitation**

```
5. Тапни "Prove again" / "Refresh" / re-mint trigger
```

### Step 3. Auth handoff

Если stock TLSN не кеширует token. ты увидишь полный OAuth re-handoff:

```
6. ASWebAuthenticationSession (iOS) / Chrome Custom Tab (Android) открывается
   → если GitHub cookie warm в Safari → consent screen
   → если consent auto-skipped (returning OAuth) → Universal Link return
7. Notarize фаза
```

**Что замеряешь.**
- Tap count к этому моменту
- Был ли ASWebAuthSession iOS consent sheet? Если ДА — это minus point vs Hack 3
- Auto-skipped GitHub consent screen на repeat? Если НЕТ — TLSN build не использует returning-user OAuth right
- App-switch animation возвращает в TLSN host-shell через Universal Link?

### Step 4. Notarize + success

```
8. Generating proof... (loading screen)
   T_notarize_start
9. Success state shown
   ┌─────── STOPWATCH STOP ────────┐
   T_end
```

**Что замеряешь.**
- T_notarize = T_end - T_notarize_start (это чистый TLSN proxy/MPC time)
- T_total = T_end - T_start

## What counts as tap

- ✓ Тап на интерактивный element (button, row, CTA)
- ✓ Тап на system sheet "Continue"
- ✓ Тап на iOS consent sheet
- ✗ Face ID / Touch ID look — **НЕ tap** (биометрия). Но в этом сценарии (stock) если build её триггерит — записывай отдельно как "biometric prompts"
- ✗ Swipe / scroll — НЕ tap
- ✗ Авто-маршрутизация через Universal Link — НЕ tap

## What counts as abandon

- Юзер закрывает app до Success state
- Юзер swipe-back из ASWebAuthSession sheet
- Юзер тапает "Cancel" в любом consent screen
- Юзер закрывает host-shell когда proof в flight

Если ты Tester и хочешь зарегистрировать abandonment rate — прогон сценарий 10 раз, запиши сколько из них успешно дошло до Success.

## Output. Заполни в comparison/template.csv row `warm-returning × github`

| Metric | Value |
|---|---|
| Taps (total) | __ |
| Seconds (T_total) | __ |
| Seconds (T_notarize only) | __ |
| App-switches | __ |
| Consent screens | __ |
| Biometric prompts | __ |
| Errors / retries | __ |
| Success rate over 10 attempts | __ / 10 |
| Notes | __ |

## Common stock-TLSN observations

1. **Если build не кеширует token** → каждый re-prove = full OAuth. Это базлайн ~5-10с warm + ~1-2с notarize = ~7-12с total.
2. **Если build кеширует но не использует биометрию** → проще, ~3-4с total. Но небезопасно (любая аппка с физическим доступом к девайсу).
3. **Если build использует MPC mode** → +13с floor на каждом proof'е. ~20-25с total = за target metric.

Записывай ВСЁ что видишь, даже если оно не вписывается в этот шаблон. Используй секцию `Notes` для observations.
