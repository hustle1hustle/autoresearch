# Hack 1 — Expected Delta

## Источник прогноза

`../../mobile-ux-deep-research.md` §1 Hack 1. Дословно:

> **Trick:** When the user lands on "Prove your GitHub" but *before* they tap, open the WebSocket to the REP verifier and load Mozilla root certs into the prover. PKCE `code_verifier` is also generated up front.
>
> **Savings:** ~500–1000 ms saved off the perceived notarize latency. With proxy mode at ~1–2 s on a real residential link, removing the WebSocket-setup tax gets us to ~0.5–1.0 s post-OAuth-return — **invisible inside the iOS app-switch animation** (which is ~400 ms baseline).

Источник для proxy mode timing — `../../00-tlsnotary.md` §6 (бенчмарки TLSNotary). Источник для Plaid pattern — [Plaid iOS docs `Plaid.create()` preload](https://plaid.com/docs/link/ios/), также cited в research.

## Predicted deltas (per scenario)

Базовое предположение. proxy mode active в TLSN build, юзер на residential 5-50 Mbps.

| Scenario | Stock baseline (s, T_notarize) | With Hack 1 (s, T_notarize) | Delta (s) | Delta % |
|---|---|---|---|---|
| warm-returning × GitHub | 1.5 | 0.7-1.0 | 0.5-0.8 | 30-50% |
| warm-first × GitHub | 1.5 | 0.7-1.0 | 0.5-0.8 | 30-50% |
| cold × GitHub | 1.5 | 0.7-1.0 | 0.5-0.8 | 30-50% |

**Important.** Hack 1 экономит на **post-tap notarize**, не на overall T_total. Если ты меряешь T_total. в warm-returning + warm-first delta видна (notarize — большая часть post-tap времени). В cold delta размывается. notarize — малая часть от 30 с total (login form доминирует).

## Где Hack 1 НЕ помогает

1. **Если build на MPC mode.** Notarize ~13 с floor. Pre-warm ~500 мс economy → < 5% delta. Невидно.
2. **Если Open Question Q2 = no separate `.connect()` API.** Hack 1 неимплементируем. delta = 0.
3. **Если pre-warm провалился (плохая сеть).** Fallback на on-demand. delta ≈ 0.

## Где Hack 1 помогает БОЛЬШЕ чем ожидалось

1. **Если proxy mode + Hack 6 stacked.** В сочетании с notarize-in-animation Hack 1 даёт invisible notarize. User не видит спиннер вообще. Это subjective win который трудно cell в Excel.
2. **Если build на slow uplink (Edge / weak 5G).** Pre-warm может сэкономить >1 с потому что WebSocket handshake сам медленный.

## Что сделать если delta меньше ожидаемого

- ✅ Сначала проверь что pre-warm IS firing (см. test-procedure.md sanity check 1)
- ✅ Затем проверь что not blocking UI (sanity check 2)
- ✅ Тогда сравни raw network timing. может сеть была лучше у baseline group чем у hack-1 group (рандомный flake)
- ✅ Если delta стабильно < 300 мс — TLSN build может уже делать internal pre-warm (что хорошо!) → отметь это как finding в `../../open-questions.md` New findings

## Что сделать если delta больше ожидаемого

- 🎉 Превосходно. Документируй точную методику и проверь на других таргетах
- 🤔 Подозрительно если delta > 2 с. Возможно ты меряешь не то. убедись что T_notarize_start фиксируется НА FIRE POST-запроса, а не на screen render

## Дополнительные expected metrics

- **Pre-warm avg duration.** 300-800 мс на residential
- **Pre-warm success rate.** > 95% на хорошей сети, > 80% на 5G weak. Если ниже — реализация плохая
- **Battery impact.** Pre-warm = открытый WebSocket пока экран ConnectGitHubView активен. Если юзер сидит на этом экране минутами, расход batter я очевидно растёт. В test-procedure добавь note что юзер не должен сидеть на screen > 30 секунд для honest measurement.

## How this stacks with other hacks

- **Hack 1 + Hack 6 = invisible notarize.** Notarize прячется в iOS app-switch animation. T_perceived (юзер subjectively) ≈ 0 ms на notarize step.
- **Hack 1 + Hack 2 = optimal warm-returning.** Pre-warm + cached refresh token + Face ID + immediate notarize. Best-case ~3 с total.
- **Hack 1 + Hack 4** ортогональны, but both нужны для clean perceived flow.

## Cite

- [Plaid Link iOS docs](https://plaid.com/docs/link/ios/) — pattern source
- `../../mobile-ux-deep-research.md` §1 Hack 1 — predicted savings + rationale
- `../../00-tlsnotary.md` §6 — proxy mode timing baseline (~1-2 s for 1KB/2KB exchange)
