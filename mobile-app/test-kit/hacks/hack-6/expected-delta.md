# Hack 6 — Expected Delta

## Источник

`../../mobile-ux-deep-research.md` §1 Hack 6:

> **Trick:** After `ASWebAuthenticationSession`'s success callback fires, iOS spends ~400 ms animating back. During that window, kick the GraphQL POST + the prover's selective-disclosure proof. The user's perception: tap GitHub → quick auth → return → "Proof ready" appears with the transition. No spinner.
>
> **Savings:** removes the ~1–2 s notarize from the *user's perceived* latency entirely on warm runs. With Hack 1 + Hack 2 + Hack 6 stacked, the warm-returning case is **1 tap, ~3 s end-to-end (just the Face ID animation), proof emitted before the user notices**.

## Predicted delta

| Metric | Stock | With Hack 6 |
|---|---|---|
| Objective T_total (s) | 7-10 | 7-10 (same) |
| **Perceived T_total** (subjective survey) | 7-10 | 3-5 |
| Loading screen visible time | 1-2 s | 0 s |
| User-reported "did it feel fast?" | mixed | "very fast" |

**Important.** Hack 6 не уменьшает objective time. Он скрывает loading state в animation. Это **perception engineering**, не computational optimization.

## Где Hack 6 НЕ помогает

1. **Если notarize > 1.5 секунд.** Animation окно ~400 мс. Если notarize 1.5+ секунды, animation done и spinner всё равно visible (просто короче).
2. **Если build на MPC mode.** ~13 секунд notarize >> 400 мс animation. Hack 6 эффективно сводится к "stage UI activates быстрее". Полезно но не magic.
3. **Если accessibility "Reduce Motion" включён.** Animation 0 мс, Hack 6 reverts на explicit stages.

## Где Hack 6 помогает БОЛЬШЕ

1. **Stacked с Hack 1 + Hack 2.** Pre-warmed WebSocket + refresh-grant ~200 мс + notarize ~500-800 мс на residential = ~700-1000 мс total. Fits в Face ID animation. Полностью invisible.
2. **Multi-endpoint kitchen-sink.** Если notarize включает несколько API calls (Strava 4 endpoints), Hack 6 + stage progress UI делает 2-3 секунды feel fast потому что user видит progress.

## Subjective vs Objective

Это самое нетипичное измерение в kit'е. Большинство хаков мерят `seconds reduced`. Hack 6 мерит `perception of time`. Methodologies:

- **A/B perceived time survey.** Двум tester'ам показать тот же flow с/без Hack 6. Ask "сколько секунд". Difference — Hack 6 delta.
- **Time-blind self-test.** Sам прогон flow, не смотри stopwatch, угадай time. Compare guess vs reality.
- **Eye-tracking (advanced).** Где tester смотрит во время notarize? Если на success state когда он появляется — Hack 6 работает. Если на спиннер — нет.

Эти methods soft. Не expect statsig with N=10. Use as direction-finding.

## Что мерять прежде всего

**Primary.** `perceived_time` (subjective survey). Должно быть 30-50% от objective time на warm-first.

**Secondary.** `stage_ui_activation_rate`. На fast network ≈ 0% (animation handles). На slow network ≈ 100%. Это checks that timeout логика работает.

**Tertiary.** `spinner_visible_duration_ms`. Время в loading state. Без Hack 6 ≈ T_notarize. С Hack 6 ≈ max(0, T_notarize - 400).

## Что сделать если delta меньше

- ✅ Verify parallel execution (animation + notarize together)
- ✅ Verify notarize starts при animation start, не после animation done
- ✅ Check accessibility settings. Reduce Motion отключает animation
- ✅ Test on real device, не simulator (animation timing differs)

## Что сделать если delta больше

- 🎉 Survey participants who say "instant" — это лучший signal что Hack 6 works
- 🤔 Document какие stages работают best, какие копи использовать

## Real-world significance

Hack 6 один of самых важных хаков для UX feel но truly hard to measure. Best way to validate. show flow к 5 random people с/без Hack 6, ask which feels faster. Если consistent answer = Hack 6 version → win.

## How this stacks

- **Hack 1** prerequisite. Без pre-warm notarize starts cold → не fits в animation.
- **Hack 2 + Hack 6 = magic warm-returning.** Face ID animation + parallel refresh + notarize → all hidden.
- **Hack 4** prerequisite. Universal Link timing критичен.
- **Hack 3, 5** ортогональны.

## Cite

- [Plaid Link docs callback ordering](https://plaid.com/docs/link/ios/) — "callback ordering is not guaranteed" pattern source
- `../../mobile-ux-deep-research.md` §1 Hack 6 — predicted invisible notarize
- `../../00-tlsnotary.md` §6 — proxy mode timing (~1-2 s baseline)
- [Nielsen Norman response time research](https://www.nngroup.com/articles/response-times-3-important-limits/) — perception thresholds (0.1s instant, 1s flow, 10s losing attention)
