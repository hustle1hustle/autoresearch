# RUN-ORDER — recommended testing sequence

Этот kit можно прогнать в любом порядке, но есть оптимальная последовательность которая минимизирует переделки и максимизирует learning early.

## Total time estimate

| Phase | Time | Per phase |
|---|---|---|
| Setup + baseline (3 scenarios × 1 target) | ~2 часа | One-time |
| Per hack (3 scenarios × 1 hero target) | ~1.5 часа × 6 | ~9 часов |
| Per hack on остальных 6 таргетах | ~30 мин × 6 хаков × 6 таргетов | ~18 часов |
| All-hacks-stacked прогон | ~3 часа | One-time |
| **Total** | **~32 часа** | для full matrix |

Если budget tight — гони только **baseline + Hack 1 + Hack 6 на GitHub hero**. Это ~5 часов и закрывает 80% value (см. expected-delta'ы в hacks/).

## Sequence

### Phase 0. Setup (30 минут)

1. Drop TLSN build в `tlsn-build/` (см. README §1)
2. Установить на тестовые девайсы (1 iPhone, 1 Android минимум)
3. Открыть `open-questions.md`. answer Q1 (proxy vs MPC support) сразу как сможешь
4. Если build только MPC. ожидаемые baseline times будут ~13с notarize вместо ~1-2с. отмечай это в каждом сценарии

### Phase 1. Baseline на GitHub hero (60 минут)

GitHub. это hero proof (см. `../04-hero-flow.md`). Меряем его первым потому что:
- самый чистый OAuth путь (in-scope plain bearer)
- стабильнейший endpoint
- наша демо для рынка

Порядок:
1. `baseline/warm-first.md` × GitHub (~20 мин)
2. `baseline/cold.md` × GitHub (~20 мин)
3. `baseline/warm-returning.md` × GitHub (~20 мин)

Заполни первые 3 строки `comparison/template.csv` колонка `stock-tlsn`.

### Phase 2. Хаки в shippability order на GitHub hero (~9 часов)

Порядок хаков по эффективности и риску (см. mobile-ux-deep-research.md §1):

**Hack 1. Pre-warm WebSocket.** Тривиально, неделя 1. Старт здесь.
- `hacks/hack-1/implementation-notes.md`
- `hacks/hack-1/test-procedure.md` × 3 scenarios × GitHub
- Заполни колонку `hack-1` в comparison/template

**Hack 6. Notarize-in-animation.** Зависит от Hack 1. ставим вторым.
- `hacks/hack-6/...` × 3 scenarios × GitHub
- Колонка `hack-6` в comparison (важно. меряем hack-6 как stack поверх hack-1)

**Hack 3. Pre-sheet explainer.** Влияет на конверсию через iOS system sheet. меряем sheet-continue-rate.
- Особенно важна iOS. на Android pre-sheet опционален (CCT silent)

**Hack 4. Universal Link auto-return.** Один раз настроил AASA, потом меряешь.

**Hack 2. Refresh token + Face ID.** Самый большой "wow" на repeat. ставим после того как warm-first работает.
- Принципиально только для `warm-returning.md` сценария

**Hack 5. Conditional UI passkey.** Применимо в основном для REP-self login. ставим последним.

### Phase 3. All-hacks-stacked прогон на GitHub (1 час)

Сложи все 6 хаков в один host-shell. Прогон 3 сценариев. Это твоё лучшее число для PM-демки.

Заполни колонку `all-hacks-stacked` в comparison.

### Phase 4. Остальные 6 таргетов (~18 часов)

Один target за раз. Для каждого:
1. Открой `targets/<target>.md`
2. Прогон baseline + all-hacks-stacked в 3 сценариях
3. Заполни строки в comparison/template

Порядок таргетов после GitHub (по простоте интеграции):
1. **Codeforces** (public API, no auth) — проще всего, ~30 мин
2. **StackOverflow** (clean OAuth)
3. **Strava** (clean OAuth, but mobile OAuth UX clunky)
4. **Duolingo** (cookie reuse, watch for Cloudflare)
5. **LeetCode** (cookie reuse, conditional Cloudflare risk)
6. **Anthropic** (admin key paste — не consumer flow, но showcase)

### Phase 5. Hand off (1 час)

1. Прогон `ANTI-PATTERNS-CHECKLIST.md` против всех своих host-shell'ов. отметь что НЕ воспроизвёл (все 10 должны быть ✓)
2. Update `open-questions.md` с answer'ами что real-device тесты разрешили
3. Финальный CSV отдай PM'у
4. Если делал особые наблюдения которых нет в research/ — добавь в `open-questions.md` секцию `## New findings`

## Если что-то ломается

- Build падает при notarize → проверь `open-questions.md` Q1. может build только MPC а ты пытаешься proxy
- Universal Link не маршрутизирует → `open-questions.md` Q3 + Bugfender debugging guide (см. mobile-ux-deep-research.md Hack 4)
- Cookie не выживает replay → `open-questions.md` Q5, fallback на MPC mode (user IP) для этого таргета
- Wall-clock сильно медленнее research'а → `open-questions.md` Q4, документируй real numbers

## Что НЕ делать в этом порядке

- Не пытайся одновременно хак и таргет если ты ещё не прогнал baseline для них. инвалидирует comparison
- Не модифицируй TLSN build. это не наш kit. host-shell only
- Не пропускай ANTI-PATTERNS-CHECKLIST. это quality gate

---

**Минимальный путь.** Если у тебя есть 5 часов и один девайс → Phase 0 + Phase 1 + Hack 1 + Hack 6 на GitHub. Принесёт самый большой single insight (~1-2 с notarize прячется в анимацию = warm returning в 1 тап).
