# Hack 1 — Pre-warm WebSocket. Test Procedure

## Setup

1. Имплементируй Hack 1 согласно `implementation-notes.md` в твоём host-shell'е
2. Verify pre-warm запускается. посмотри в логах `notarize_websocketConnected` event с `stage: "prewarm"` появляется ДО любого таптания
3. Build установлен на тестовый девайс (iOS / Android)

## Measurement points

- **T_appear.** ConnectGitHubView появился на экране
- **T_prewarm_done.** WebSocket к verifier'у открыт (`prover.session.isActive == true`)
- **T_user_tap.** Юзер тапнул "Continue with GitHub"
- **T_oauth_return.** Universal Link вернул в host-shell с code
- **T_notarize_start.** GraphQL request fired через TLSN
- **T_notarize_done.** Proof готов
- **T_end.** Success state shown

## Test variants

### Variant A. Warm returning (где Hack 1 наиболее important)

Стандартный warm-returning сценарий из `../../baseline/warm-returning.md`, но host-shell имеет Hack 1.

**Hypothesis.** T_notarize_done - T_user_tap уменьшается на ~500-1000 мс vs stock baseline. Чистый proxy notarize (~1-2с per [`../../00-tlsnotary.md`](../../00-tlsnotary.md) §6) минус pre-warm-saved time.

### Variant B. Warm first

Из `../../baseline/warm-first.md`, host-shell имеет Hack 1.

**Hypothesis.** Та же экономия ~500-1000 мс на notarize step. Other parts (OAuth handoff, GitHub consent) не затронуты.

### Variant C. Network adversarial

Прогон Variant A под bad network. iPhone в Settings → Developer → Network Link Conditioner → "Edge" или "3G". Hack 1 должен SAFELY провалиться. Юзер не должен видеть error — только обычный non-Hack-1 timing.

**Hypothesis.** T_oauth_return - T_user_tap unchanged (это OAuth, not network-limited на нашей стороне). T_notarize_done - T_oauth_return = normal cold-start TLSN time (pre-warm не успел).

## Stopwatch script

Это можно делать вручную (с реальным stopwatch'ем) или через injected analytics events. Если используешь analytics:

```
event.notarize_websocketConnected (stage=prewarm) → T_prewarm_done
event.cta_tap (cta=continue_github)                → T_user_tap
event.webauth_universalLinkReturn                  → T_oauth_return
event.notarize_responseReceived                    → T_notarize_done
event.success                                      → T_end
```

Используй `../../measurement/event-spec.md` для полного event list.

## Procedure (per scenario)

### Setup для каждого attempt

```
1. Force-quit host-shell
2. Re-open. cold start
3. Navigate to ConnectGitHubView (entry point)
4. WAIT 2 секунды (даём pre-warm закончиться)
5. Observe T_prewarm_done event в logs / analytics console
```

### Attempt

```
6. Tap "Continue with GitHub"  → T_user_tap
7. (OAuth flow runs)
8. Return в host-shell           → T_oauth_return
9. Notarize completes            → T_notarize_done
10. Success state                → T_end
```

### Compute

```
prewarm_time = T_prewarm_done - T_appear
notarize_time_with_hack1 = T_notarize_done - T_oauth_return
oauth_time = T_oauth_return - T_user_tap (для context)
total_perceived = T_end - T_user_tap
```

### Repeat 10 attempts per variant

Median across 10 — это твой output.

## Output. Заполни в comparison/template.csv column `hack-1`

| Metric | warm-returning × github | warm-first × github | cold × github |
|---|---|---|---|
| Median T_total (s) | __ | __ | __ |
| Median T_notarize (s) | __ | __ | __ |
| Median delta vs stock baseline (s) | __ | __ | __ |
| Pre-warm success rate | __ / 10 | __ / 10 | __ / 10 |
| Pre-warm avg duration (ms) | __ | __ | __ |
| Network: Wi-Fi | __ s | __ s | __ s |
| Network: 5G | __ s | __ s | __ s |
| Network: Edge (bad) | __ s | __ s | __ s |

## Sanity checks

1. **Pre-warm IS firing before user tap.** Если в логах T_prewarm_done > T_user_tap, ты не имплементировал Hack 1 правильно. Pre-warm должен запускаться при View `.task` или ViewModel `init`.
2. **Pre-warm DOESN'T block UI.** Если CTA button недоступна пока pre-warm идёт, ты блокируешь UI. Это анти-паттерн. См. implementation-notes.md.
3. **Pre-warm survives backgrounding gracefully.** Если юзер минимизировал app и вернулся через минуту, и pre-warm не reset'нулся — ты можешь говорить с мёртвым WebSocket'ом. Implement `.onChange(of: scenePhase)` re-prewarm.

## Common observations

1. **Wi-Fi.** Pre-warm даёт чистые ~500 мс экономии. Notarize дрожит вокруг ~1.5 с. Total saving в perceived terms ~30%.
2. **5G good.** Похоже на Wi-Fi.
3. **5G weak.** Pre-warm может занять ~2-3 с, но успевает закончиться к моменту тапа (т.к. юзер тоже медленнее тапает). Net effect — exposed.
4. **Edge / Bad network.** Pre-warm провалился. Fallback на on-demand работает но медленно. Юзеру нужно показать loading state.

## Pass/fail criteria для этого хака

✅ **PASS** если. median delta для warm-returning ≥ 300 мс vs stock baseline AND zero UI-blocking AND graceful failure under bad network.

❌ **FAIL** если. delta < 100 мс (имплементация broken) ИЛИ pre-warm блокирует UI ИЛИ host-shell падает когда pre-warm провалился.
