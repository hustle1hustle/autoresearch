# Open Questions — что real-device тесты должны разрешить

Список вопросов, на которые этот kit отвечает прогоном на реальном железе. Каждый вопрос помечен. **OPEN** / **PARTIAL** (есть данные но не полные) / **RESOLVED** (есть ответ с цифрой).

Tester обновляет статусы по мере прогона.

---

## Q1. Mode support в TLSN mobile build. proxy / MPC / оба?

**Why it matters.** Все expected-delta'ы в `hacks/` основаны на ~1-2 с notarize (proxy). Если build только MPC — реальные deltas размажутся по ~13 с floor и сравнение с research'ем будет искажено.

**Where to check:**
- `tlsn-build/<platform>/` config files. Look for `MpcTlsConfig` / `ProxyTlsConfig` enum usage.
- TLSN repo origin commit (если есть `.git/`). Знай что proxy mode merged в `crates/examples/proxy/proxy.rs` после April 2026 (`../00-tlsnotary.md` §2).
- Try running a notarize. посмотри в логах. указывается mode.

**Status.** `OPEN`

**If MPC-only:** все expected-delta'ы в `hacks/` для warm-returning будут показывать абсолютные числа ~13 с, а не ~3-4 с. Hack 6 (notarize-in-animation) станет неприменим. отметь это в test-procedure'ах.

**RESOLVED when.** "Build supports proxy = YES/NO, MPC = YES/NO. Default mode = ___. Tested on iOS/Android via ___ command."

---

## Q2. Hooks для pre-warming verifier WebSocket?

**Why it matters.** Hack 1 (pre-warm на screen mount) экономит ~500-1000 мс perceived latency, но требует чтобы prover API в TLSN build разделял `connect()` и `prove()` фазы. Если они слиты в один blocking call — Hack 1 неимплементируем без forking'а TLSN.

**Where to check:**
- SDK / library headers в `tlsn-build/`. Look for `Prover.connect()`, `ProverSession.new()`, или похожих.
- Если есть `Prover::open_websocket()` отдельно от `Prover::run()` — Hack 1 implementable.
- Если только blocking `Prover.notarize(target, request)` — нужен forking подход или мы не можем сделать Hack 1.

**Status.** `OPEN`

**If no separation:** Hack 1 deltas будут 0 (нечего pre-warm'ить). Документируй в `hacks/hack-1/test-procedure.md` секции "Build limitation".

**RESOLVED when.** "WebSocket open API = ___ (path + function). Pre-warm time captured = ___ ms. Implementation viability = YES/NO."

---

## Q3. Universal Link auto-return supported или custom URL schemes only?

**Why it matters.** Hack 4 (Universal Link auto-return) предотвращает ~30% swipe-back drop-off ([Plaid Link docs](https://plaid.com/docs/link/ios/)). Если TLSN build вшит на custom URL schemes — нужен патч host-shell'а который перехватывает.

**Where to check:**
- `tlsn-build/ios/.../Info.plist` — секция `CFBundleURLTypes` (custom schemes) vs `com.apple.developer.associated-domains` entitlement
- `tlsn-build/android/AndroidManifest.xml` — `<intent-filter>` с `android:autoVerify="true"` для App Links
- Если build использует `tlsn://callback` или похожие — это custom scheme. неэкологично, не предотвращает поджокинг другими аппками.

**Status.** `OPEN`

**Action if custom scheme:** Host-shell должен перехватить URL в `application(_:open:options:)` и сам маршрутизировать. Hack 4 переезжает в host-shell ответственность, а не TLSN build.

**RESOLVED when.** "Universal Link domain = ___. AASA path = ___. Tested return from Safari OAuth = успех/swipe-back required."

---

## Q4. Real wall-clock per Tier-1 target на residential Wi-Fi / 5G

**Why it matters.** `mobile-ux-deep-research.md` цели. warm returning ≤ 7 с, cold ≤ 30 с. Эти цели взяты из TLSN benchmark'а (`../00-tlsnotary.md` §6). Реальная сеть. Wi-Fi с jitter, 5G с пиковыми задержками, корпоративный proxy. может выйти иначе.

**Where to check.** Прогон Phase 1 (baseline GitHub) и Phase 4 (other targets) с stopwatch'ем + сетевой инструментацией:

- Wi-Fi. подключись к публичному Wi-Fi или residential 5-50 Mbps
- 5G. mobile data
- 5G со слабым сигналом. в подвале / в лифте

**Заполни таблицу.** в каждой строке прописывай wall-clock как (warm-returning / warm-first / cold) для каждого target × network combo.

| Target | Wi-Fi (5-50 Mbps) | 5G (good signal) | 5G (weak signal) |
|---|---|---|---|
| GitHub | __ / __ / __ s | __ / __ / __ s | __ / __ / __ s |
| Strava | __ / __ / __ s | __ / __ / __ s | __ / __ / __ s |
| Duolingo | __ / __ / __ s | __ / __ / __ s | __ / __ / __ s |
| Codeforces | __ / __ / __ s | __ / __ / __ s | __ / __ / __ s |
| StackOverflow | __ / __ / __ s | __ / __ / __ s | __ / __ / __ s |
| LeetCode | __ / __ / __ s | __ / __ / __ s | __ / __ / __ s |
| Anthropic | __ / __ / __ s | __ / __ / __ s | __ / __ / __ s |

**Status.** `OPEN`

**RESOLVED when.** Таблица заполнена. Median warm-returning через все target × network ≤ 7 с? YES/NO.

---

## Q5. Cookie-replay durability per cookie-path target

**Why it matters.** Duolingo, LeetCode и Spotify (если когда-нибудь) используют cookie-path proof'ы. TLSNotary запускает свежую TLS-сессию из verifier, реплая cookie. Если cookie pinned к User-Agent / IP / device fingerprint — proof провалится с auth-error.

**Where to check:**
- Duolingo. реплай `jwt_token` cookie из новой TLS сессии. отдаёт ли endpoint `/2017-06-30/users/{id}` валидный JSON или 401?
- LeetCode. реплай `LEETCODE_SESSION` + `csrftoken`. отдаёт ли `/graphql` правильные данные?

**Action if fails.** Поднять прокси через MPC mode (юзер IP) для этого таргета. Документируй в `targets/<target>.md` mode recommendation.

**Status.** `OPEN`

**RESOLVED when.** "Duolingo cookie replay = выживает/умирает (IP / UA pinning). LeetCode cookie replay = выживает/умирает. Mitigation = ___."

---

## Q6. AASA TestFlight delays

**Why it matters.** iOS sometimes fetches `apple-app-site-association` со delayом до 15 минут после установки через TestFlight ([Apple Forums thread](https://developer.apple.com/forums/thread/108339)). Если host-shell тестируется через TestFlight — Universal Link может первое время не работать.

**Where to check:**
- Установи host-shell через TestFlight (не Xcode прямой run)
- Сразу попробуй Universal Link return. свайп-бэк требуется или auto-route?
- Подожди 15 минут. попробуй ещё раз
- Зарегистрируй задержку. это onboarding QA reality

**Status.** `OPEN`

**RESOLVED when.** "AASA fetch delay observed = ___ minutes after TestFlight install. Workaround = ___ (например fallback web-страница на callback URL'е с "Open in REP" deep-link button до того как AASA fetcheded)."

---

## New findings

Сюда добавляй наблюдения которые **не покрыты** в `../mobile-ux-deep-research.md` или которые её **противоречат**. Это input для следующей итерации research'а.

### N1. _________

(template для tester'а)

**Discovered:** [что неожиданное произошло]
**Context:** [какой хак, target, scenario]
**Evidence:** [скриншот / лог / время / event-tape]
**Implications:** [что меняется в playbook'е если это подтвердится]
