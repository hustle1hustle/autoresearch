# Baseline. Warm First. Stock TLSN Mobile Build

**Сценарий.** Юзер впервые минтит GitHub proof в этом app'е, НО он залогинен в GitHub в Safari (или нативной GitHub app) на этом девайсе. Cookies / OAuth session warm на платформенном уровне.

**Target metric** (из `../mobile-ux-deep-research.md`). **2-3 тапа / ≤ 7 с total**, все хаки активны.

**Stock TLSN expectation.** 3-5 тапов / ~8-15 с. iOS consent sheet + GitHub OAuth consent + любые дополнительные TLSN steps + notarize.

---

## Pre-conditions

- Stock TLSN build установлен на тестовый девайс СВЕЖЕ (первый запуск)
- ВАЖНО. удалить host-shell Keychain entries / app data между прогонами этого сценария:
  - iOS. удалить app целиком + переустановить (Keychain очищается)
  - Android. `adb shell pm clear <package>` (App data cleared)
- Юзер залогинен в GitHub.com в Safari ИЛИ в нативной GitHub app
- Wi-Fi residential или 5G good signal

## Test procedure

### Step 0. Cold app launch

```
1. Установи / переустанови TLSN host-shell
2. Tap app icon на home screen
   ┌─── STOPWATCH START (T_start) ───┐
3. Дождись first interactive frame
```

### Step 1. Onboarding если есть

Stock TLSN может показать onboarding (welcome / permissions / etc):
```
4. Прокликай onboarding до main screen
```

**Что замеряешь.** Сколько таптов между launch и main screen? Это **onboarding tax** что мы не учитываем в research'е но влияет на real-world UX.

### Step 2. Trigger first GitHub proof

```
5. Найди "Add GitHub" / "Connect GitHub" / "+ Add platform" CTA
6. Tap it
```

### Step 3. OAuth handoff

```
7. ASWebAuthenticationSession iOS sheet → "Continue"
   (или CCT silent на Android — без шита)
8. Safari открывается с GitHub OAuth page
9. Warm cookie → consent page сразу (no login form)
10. "Authorize REP" → tap
```

**Что замеряешь.**
- Tap count к этому моменту
- ЕСТЬ ли iOS consent sheet "App wants to use github.com to Sign In"? **(Если ДА, без Hack 3 это scary — фиксируем как baseline)**
- GitHub auto-показывает consent на repeat? (На FIRST attempt consent screen всегда есть)
- Universal Link или custom scheme возвращает в TLSN host-shell?
- App-switch animation плавная или прерывистая?

### Step 4. Token exchange (background)

Стандартно. PKCE code → access_token. Это background, не visible юзеру.

```
11. App вернулся в foreground
12. Optional. host-shell может показать "Confirming…" / "Generating…"
```

### Step 5. Notarize

```
13. "Generating proof" loading state
    T_notarize_start
14. Proof готов. Success screen
    ┌─── STOPWATCH STOP (T_end) ───┐
```

**Что замеряешь.**
- T_notarize
- T_total
- Какой loading copy показывает stock build? ("Loading…", "Generating…", "Please wait…", etc) — это input для ANTI-PATTERN "Spinner without context"

## What counts as tap

См. `warm-returning.md` § "What counts as tap".

## What counts as abandon

См. `warm-returning.md` § "What counts as abandon".

## Output. Заполни в comparison/template.csv row `warm-first × github`

| Metric | Value |
|---|---|
| Taps (total) | __ |
| Seconds (T_total) | __ |
| Seconds (T_notarize only) | __ |
| App-switches | __ |
| Consent screens (iOS + GitHub) | __ + __ = __ |
| Biometric prompts | __ |
| Errors / retries | __ |
| Success rate over 10 attempts | __ / 10 |
| Onboarding tax (taps before main CTA) | __ |
| Spinner copy used | "____________" |
| Notes | __ |

## Special focus в warm-first vs warm-returning

В warm-first ты МЕРЯЕШЬ tax от:
1. iOS consent sheet (никак без Hack 3 не предотвратить)
2. GitHub OAuth consent screen первого раза (auto-skipped на repeat'ах)
3. Universal Link return (или его отсутствие)

Если stock build БЕЗ Hack 3 показывает iOS sheet и юзер абандонит — это твой baseline drop point.
Целевой: с Hack 3 sheet-continue-rate > 80% (см. `../mobile-ux-deep-research.md` §1 Hack 3).

## Common stock-TLSN observations

1. **Onboarding tax 2-3 тапа** — typical для multi-screen onboarding'а ("Welcome", "Permissions", "Get started")
2. **iOS consent sheet drop** — без pre-explainer's, conversion ~75-85%. С Hack 3 целишь в 95%+
3. **Generating spinner без копии** — anti-pattern. Stock TLSN скорее всего показывает generic "Loading…"
