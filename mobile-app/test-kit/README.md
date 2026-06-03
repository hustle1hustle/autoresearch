# AIO Test Kit — REP UX Hacks on TLSNotary Mobile

Test kit для measurable validation 6 UX-хаков из `mobile-ux-deep-research.md` против stock TLSNotary mobile build на всех 8 Tier-1 платформах.

**Цель.** Warm returning ≤ 2 тапа / ≤ 7 с. Cold ≤ 5 тапов / ≤ 30 с. Beat stock TLSN на каждой drop-off точке.

## Quick start

Если ты new dev. **start with [`setup/06-first-proof-walkthrough.md`](setup/06-first-proof-walkthrough.md)** — zero-to-success на твоём iPhone за ~30 минут. Pre-reqs там и references на остальные setup гайды.

Если ты возвращаешься. см. `RUN-ORDER.md` для testing flow.

Если что-то сломалось. **[`troubleshooting.md`](troubleshooting.md)** в корне kit'а. Common failures + fixes consolidated.

## Что внутри

```
test-kit/
├── README.md                  ← ты здесь
├── RUN-ORDER.md               ← рекомендованная последовательность тестов
├── ANTI-PATTERNS-CHECKLIST.md ← печатный one-pager что НЕ делать
├── open-questions.md          ← 5 questions для real-device тестов
├── troubleshooting.md         ← consolidated common failures + fixes
├── setup/                     ← end-to-end setup guides (start here)
│   ├── README.md              ← когда что читать
│   ├── 01-xcframework-build.md   ← TLSN prover → .xcframework
│   ├── 02-oauth-apps.md          ← GitHub + Strava + StackOverflow OAuth setup
│   ├── 03-self-hosted-notary.md  ← Docker notary с whitelist
│   ├── 04-universal-links.md     ← AASA + entitlement + testing
│   ├── 05-cookie-probe.md        ← Safari Inspector для cookie names
│   └── 06-first-proof-walkthrough.md ← zero to success на real iPhone
├── tlsn-build/                ← DROP YOUR TLSN MOBILE BUILD HERE
├── baseline/                  ← 3 stock-TLSN сценария (control group)
│   ├── warm-returning.md
│   ├── warm-first.md
│   └── cold.md
├── hacks/                     ← 6 хаков, по 3 файла на каждый
│   ├── hack-1/  pre-warm WebSocket
│   ├── hack-2/  refresh token + Face ID
│   ├── hack-3/  pre-sheet explainer
│   ├── hack-4/  Universal Link auto-return
│   ├── hack-5/  conditional UI passkey
│   └── hack-6/  notarize-in-animation
├── targets/                   ← 8 платформ. OAuth, endpoint, redaction
│   ├── github.md  ← HERO
│   ├── strava.md
│   ├── duolingo.md
│   ├── luma.md
│   ├── codeforces.md
│   ├── stackoverflow.md
│   ├── leetcode.md
│   └── anthropic.md
├── measurement/               ← event spec + ready-to-paste snippets
│   ├── event-spec.md
│   ├── capture-ios.swift.snippet
│   └── capture-android.kt.snippet
└── comparison/                ← side-by-side matrix template
    ├── template.csv
    └── template.md
```

## Quickstart

### 1. Drop the build (5 минут)

Положи TLSNotary mobile build в `tlsn-build/`. Если у тебя iOS build:
```bash
cp -R ~/path/to/TLSNotary.app tlsn-build/ios/
```
Android:
```bash
cp ~/path/to/tlsnotary.apk tlsn-build/android/
```

Если build умеет proxy mode — отметь это в `open-questions.md` строке 1.

### 2. Baseline measurement (60 минут, по 20 на сценарий)

Установи stock build на тестовый девайс БЕЗ модификаций. Открой `baseline/warm-returning.md`, следуй tap-by-tap скрипту, заноси цифры в `comparison/template.csv` row 1.

Повтори для `warm-first.md` и `cold.md`. Это control group, против которой меряем все хаки.

**Минимальный набор девайсов.** 1 iPhone (iOS 17+) + 1 Android (14+). Идеально. ещё iPhone на iOS 18 для Hack 5.

### 3. Apply hack N (30-60 минут per hack)

Открой `hacks/hack-N/implementation-notes.md`. Это инструкции для host-shell приложения вокруг TLSN build. ТЫ НЕ МОДИФИЦИРУЕШЬ TLSN. ты пишешь обёртку.

Затем `hacks/hack-N/test-procedure.md`. прогон с инструментированием.

Цифры в `comparison/template.csv` колонка `hack-N`.

### 4. Compare и hand off

После всех 6 хаков прогнан + `all-hacks-stacked` колонка — отдай `comparison/template.csv` PM'у. Он читает как self-explanatory artifact.

## Порядок тестов

См. `RUN-ORDER.md`. TL;DR. baseline → 1, 6, 3, 4, 2, 5. По shippability, не по номеру.

## Что нельзя

См. `ANTI-PATTERNS-CHECKLIST.md`. Tester тикает каждый антипаттерн что НЕ воспроизвёл в своём host-shell'е.

## Если что-то непонятно

`open-questions.md` — список вопросов которые этот kit разрешит. Если real-device тест отвечает на пункт N, перепиши его как "RESOLVED" с цифрами.

Для глубины. `../mobile-ux-deep-research.md` (полный research), `../ROUTING.md` (decisions), `../04-hero-flow.md` (hero spec с Rust skeleton), `../login-overview.html` (визуально + моки).

---

**Кит должен быть self-contained.** Если эта инструкция чего-то не покрывает — это баг кита, отметь в `open-questions.md`.
