# Hack 6 — Notarize-in-Animation. Test Procedure

## Setup

1. **Hack 1 уже implemented и tested.** Без pre-warm нет смысла Hack 6.
2. Hack 6 implemented per `implementation-notes.md`
3. Host-shell имеет stage UI который активируется на timeout (если notarize > 2s)

## Measurement points

- **T_oauth_return.** Universal Link auto-return triggered
- **T_animation_start.** Host-shell view transition начался
- **T_notarize_start.** notarize fired (parallel с animation)
- **T_animation_done.** ~400ms iOS app-switch animation done
- **T_notarize_done.** Proof готов
- **T_success_shown.** Success state visible to user

## Test variants

### Variant A. Fast network. notarize прячется в animation

```
1. Wi-Fi residential
2. Run warm-first flow с Hack 1 + Hack 6 enabled
3. Complete OAuth handoff
4. Observe: app-switch return animation
5. Observe: success state появляется до или сразу после animation done
6. Юзер perception: тап → done без visible spinner
```

**Hypothesis.** T_success_shown - T_oauth_return < 1000 ms. User survey ("Сколько секунд это заняло?") отвечает "0-1 секунду".

### Variant B. Slow network. notarize выходит за animation

```
1. Network Link Conditioner: 3G profile
2. Run same flow
3. Observe: animation done at ~400ms
4. Observe: notarize ещё идёт (~3-5 секунд на slow network)
5. Observe: после animation → stage progress visible
6. Юзер perception: тап → quick animation → "Confirming with notary..." → done
```

**Hypothesis.** T_success_shown - T_oauth_return ~= 4-6 секунд. Юзер видит stages, не stuck. Не падает в "Spinner without context".

### Variant C. Notarize fails mid-animation

Forced. отключить network mid-flow.

```
1. OAuth complete, animation start
2. Disable Wi-Fi прямо во время animation
3. Notarize fails
4. Observe: host-shell показывает recoverable error UI ("Connection dropped. Try again — we don't keep anything from the failed attempt.")
5. Юзер тапает Retry → notarize fires снова с saved access_token
```

**Hypothesis.** Graceful failure. Не падает. Retry работает потому что access_token ещё валиден (8h GitHub).

### Variant D. MPC mode build

Если TLSN build только MPC:

```
1. Run flow с Hack 1 + 6 enabled
2. Notarize занимает ~13 секунд
3. Animation done at 400 ms
4. Stage progress visible ~12-13 секунд
```

**Hypothesis.** Hack 6 эффективно не работает (animation окно тoo small для MPC). Stage progress dominates UX. Document в test output.

## Subjective measurement

Hack 6 особенный потому что объективное время (T_total) может быть тоже самое как без Hack 6, но **perceived time** меньше.

Conduct simple survey после Variant A:
```
"Сколько секунд это заняло?"
Options: 0 sec | 1 sec | 2 sec | 3 sec | 4+ sec
```

Tester опрашивает 10 разных людей (или себя через time-blind testing). Compare perceived time vs actual T_total.

**Target.** average perceived < 50% of actual T_total. Это и есть suspect-bias-but-real Hack 6 win.

## Output. Заполни в comparison/template.csv column `hack-6`

| Metric | warm-first × github | warm-returning × github |
|---|---|---|
| Median T_total objective (s) | __ | __ |
| Median perceived time (subjective) | __ | __ |
| Stage UI activation rate (timeout > 2s) | __ % | __ % |
| Recovery success on mid-notarize failure | __ / 10 | __ / 10 |
| Notes | __ | __ |

## Sanity checks

1. **Parallel execution actually parallel.** Используй Instruments / DDMS profiler чтобы verify animation и notarize startedся одновременно. Если sequential — реализация broken.
2. **Stage UI showed correctly on timeout.** Force slow network. После 2 секунд должен переключиться на stages, не spinning forever.
3. **Success state appears smoothly.** Если success appears mid-animation — глючно. Должен либо до animation либо после, не overlap.
4. **No "Loading…" copy.** Если на slow network твой stage UI говорит "Loading…" — anti-pattern fail.

## Pass/fail criteria

✅ **PASS** если:
- Variant A. Perceived time < 50% of objective time
- Variant B. Stage UI properly активируется, юзер видит progress
- Variant C. Recovery работает без app crash
- No "Loading…" / "Please wait…" copy anywhere

❌ **FAIL** если:
- Animation и notarize sequential (notarize не параллелен)
- Stage UI not appear когда нужен
- Recovery broken
- Generic spinner copy
