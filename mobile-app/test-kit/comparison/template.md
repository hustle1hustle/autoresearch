# Comparison Matrix — how to use

Этот файл объясняет как заполнять `template.csv` и как читать result.

## Структура CSV

```
scenario, target, metric, stock_tlsn, hack_1, hack_2, hack_3, hack_4, hack_5, hack_6, all_stacked, notes
```

- **scenario.** `warm-returning` | `warm-first` | `cold`
- **target.** `github` | `strava` | `duolingo` | `codeforces` | `stackoverflow` | `leetcode` | `anthropic`
- **metric.** specific measurement (taps, seconds, success rate, etc)
- **stock_tlsn.** baseline value (без хаков)
- **hack_X.** value с этим конкретным хаком, поверх stock
- **all_stacked.** value с **всеми** хаками одновременно
- **notes.** observations, edge cases, anomalies

## Каждая cell. что в неё пишешь

| Cell type | Example | Meaning |
|---|---|---|
| Empty | `` | Not tested yet. Default state. |
| Number | `3.4` | Median value (P50 over 10 attempts) |
| Range | `3.4-4.1` | If high variance, range |
| `n/a` | `n/a` | Hack не применим к этой scenario × target combo |
| `n/a (no oauth)` | `n/a (no oauth)` | Reason inline |
| `bug` | `bug` | Hack broken для этого combo, see notes |
| `incomplete` | `incomplete` | Tested but incomplete data, see notes |

## Metric definitions

### Time metrics (seconds)

- **t_total_p50_s.** Median total time от CTA tap до Success state shown. P50 over 10 attempts.
- **t_notarize_p50_s.** Median time от OAuth return до notarize done.
- **perceived_s.** Subjective time. ask "сколько секунд это заняло?" after each attempt. Median.
- **t_login_form_s.** Cold only. time spent typing credentials.
- **t_2fa_s.** Cold only. time на 2FA challenge.

### Tap metrics

- **taps_median.** Median user-tap count. Согласно `baseline/warm-returning.md` § "What counts as tap".

### Conversion rates (% или fraction)

- **success_rate_of_10.** Successful proof completions / 10 attempts.
- **sheet_continue_rate.** webauth.systemSheetContinue / webauth.systemSheetShown.
- **ul_return_rate.** universalLinkReturn / consentApproved.
- **cookie_replay_success.** Cookies actually work in fresh TLS session.
- **cf_challenge_rate.** Cloudflare challenges / 10 attempts.

### Categorical

- **abandon_stage_top.** Most common stage where user abandoned. e.g. `systemSheet`.
- **silent_cct_android.** `yes` / `no` / `n/a`. Did Android CCT work silently без consent sheet?

## Reading the matrix

### Hack effectiveness

Compare `stock_tlsn` vs `hack_N` row. Per-hack delta should match expected-delta predictions.

Пример:
```
warm-returning, github, t_total_p50_s, 7.2, 6.5, 3.8, 7.0, 7.0, n/a, 6.3, 3.5, ...
```

- Hack 1 saves 0.7 секунд (matches expected ~500-1000 ms)
- Hack 2 saves 3.4 секунды (matches expected -2 to -6 s)
- Hack 6 saves 0.9 секунд objective (perceived much больше)
- **All stacked. 3.5 секунд** — matches the magic "warm returning in ~3-4 s" target!

### Hack interactions

Sometimes hacks combine non-linearly. Example. Hack 1 alone saves 0.5 с, Hack 6 alone saves 0.9 с, but Hack 1+6 saves 1.5 с (more than sum) потому что Hack 6 polices Hack 1's pre-warmed state.

`all_stacked` column reveals interactions. If it's much less than sum of individuals — significant interaction. Document в notes.

### Where hacks NOT working

If `hack_N` value не differs from `stock_tlsn` significantly:
- ✅ Check expected-delta. Maybe это targeted scenario где hack не помогает (например Hack 5 на GitHub direct OAuth)
- ✅ Check implementation. Run sanity checks в test-procedure
- ✅ Check sample size. N=10 не shows < 200ms differences statistically

## Hand-off к PM

Final delivery to PM. CSV + 1-page summary с:

1. **Best case combo.** Which hack stack + target gives best UX
2. **Surprise findings.** Hacks that beat / missed expectations
3. **Blockers.** What can't be tested / shipped given current build limitations (link `open-questions.md`)
4. **30-day ship recommendation.** Which hacks ready, which need more polish

## CSV → spreadsheet workflow

```bash
# Open в Excel / Numbers / Google Sheets
open template.csv

# Or import в Python для analysis:
python3 -c "
import pandas as pd
df = pd.read_csv('template.csv')
print(df.pivot_table(index=['scenario','target'], columns='metric', values='all_stacked'))
"
```

## Bonus. визуализация

Если ты хочешь сделать heatmap или bar chart:

```python
import pandas as pd
import matplotlib.pyplot as plt

df = pd.read_csv('template.csv')
totals = df[df['metric'] == 't_total_p50_s']
totals.plot(x='target', y=['stock_tlsn', 'all_stacked'], kind='bar')
plt.title('Total time per target. stock vs all hacks')
plt.savefig('comparison-bar.png')
```

Это можно прикрепить к PM presentation.

## Template самообновляется

Если ты open'ишь template.csv и видишь missing rows для scenarios/targets/metrics — add them. Это шаблон, не immutable. New finding? New row. Document причину в notes.

## Что НЕ забывать

1. **Device variants.** Test и iOS и Android. Если только iOS — соответствующий метаданные в notes.
2. **Network variants.** Wi-Fi, 5G good, 5G weak. Document в notes если major delta.
3. **Sample size.** 10 attempts на cell. Меньше = caveat в notes.
4. **Real-user vs self-test.** Self-test biased. Mark в notes "tester self" vs "user surveyed".

---

**Hand-off readiness.** CSV считается ready если каждая row для GitHub полностью заполнена. Other targets могут быть partial с notes "TODO".
