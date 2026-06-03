# ANTI-PATTERNS CHECKLIST — printable one-pager

Полный список в `../mobile-ux-deep-research.md` §6. Этот файл — печатный гейт для tester'а. Прогоняешь host-shell с каждым хаком через этот чеклист. Если воспроизводишь анти-паттерн — это баг твоего host-shell'а, не фича TLSN.

**Pass criteria.** все 10 пунктов = ✓ (не воспроизведено) для каждого хака.

---

## Tester. _________ · Date. _________ · Host-shell. _________

### Loading + success states

- [ ] **"Spinner without context"** — нет `ProgressView()` с надписью "Loading…" или без копии. Каждое ожидание называет шаг через `✓ / ● / ○`.
- [ ] **"Did it work?"** — есть явный success state с фактом (`octocat · 1,234 contributions`). Не тихое закрытие модала.
- [ ] **"What was just proved"** — есть expandable "What was proved" card. Показывает request, revealed bytes, redacted bytes, нотариус, expiry.

### Auth handoff

- [ ] **"Lost in inbox"** — нет magic-link как primary/secondary метода. OTP-код только если email обязателен.
- [ ] **"Where did I come from"** — после OAuth юзер возвращается в host-shell автоматически через Universal Link (iOS) / App Link (Android). Не оставляет в Safari/Chrome со swipe-back требованием.
- [ ] **"Scary system sheet"** — на iOS перед `ASWebAuthenticationSession` показывается pre-sheet с объяснением. Только первый раз, потом флаг в UserDefaults.
- [ ] **"App-switch you can't trust"** — host-shell НЕ использует `WKWebView` для password entry на чужих сайтах. Только `ASWebAuthSession` (URL виден) или нативный app-switch (chrome виден).
- [ ] **"Branded sheet on third-party login"** — во время handoff бренд таргета (GitHub / Strava / ...) доминирует. REP chrome subtle. Не "REP is verifying GitHub" с большим REP-логотипом.

### Repeat use

- [ ] **"Re-prove every time"** — на повторе того же proof'а Hack 2 работает. Face ID + silent refresh-grant + notarize. НЕ полный OAuth дансом.

### Permission timing

- [ ] **"Permission requested before purpose"** — биометрия prompt появляется только когда host-shell её реально использует (перед сохранением в Keychain). Push permission — только после первого успешного proof'а.

---

## Если воспроизвёл

Не пиши workaround в test-procedure. это баг host-shell'а. Возвращайся к `hacks/hack-N/implementation-notes.md` и проверь, что ты реализовал хак правильно. Если хак сам по себе провоцирует анти-паттерн — это значит хак сломан и нужно репортить в `open-questions.md`.

## Где это правило сильнее всего

- Hack 1 + Hack 6 → "Spinner without context" риск (если notarize не успевает спрятаться в анимацию, нужен правильный stage UI)
- Hack 3 → "Scary system sheet" фикс (pre-sheet это сам фикс)
- Hack 4 → "Where did I come from" фикс
- Hack 2 → "Re-prove every time" + "Permission before purpose" фиксы

---

**Подпись tester'а после прогона.** ____________

**Дата.** ____________

**Девайс.** ____________
