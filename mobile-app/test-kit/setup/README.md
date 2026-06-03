# Setup — end-to-end guides

Каждый гайд = одна end-to-end задача. Copy-paste commands, specific configuration values, common pitfalls flagged.

Не общая теория. Если ты не знаешь SwiftUI/Docker/OAuth fundamentals — это документация Apple/Docker/GitHub.

## When to read what

| Когда читаешь | Какой guide | Что получаешь |
|---|---|---|
| Item ⑧ PLAN.md (real prover swap) | [01-xcframework-build.md](01-xcframework-build.md) | TLSN prover как .xcframework |
| Item ③ PLAN.md (OAuth+UL) | [02-oauth-apps.md](02-oauth-apps.md) | GitHub + Strava + SO OAuth Apps с правильными redirect URIs |
| Item ⑧ PLAN.md (verifier wiring) | [03-self-hosted-notary.md](03-self-hosted-notary.md) | Docker notary с whitelist'ом всех Tier-1 |
| Item ③ PLAN.md (Universal Links) | [04-universal-links.md](04-universal-links.md) | AASA hosting + entitlement + dev/prod testing |
| Cookie-path targets (Duolingo/LeetCode/LinkedIn/Luma) | [05-cookie-probe.md](05-cookie-probe.md) | Конкретные cookie names через Safari Inspector |
| Перед первым real-device тестом | [06-first-proof-walkthrough.md](06-first-proof-walkthrough.md) | Zero-to-success на твоём айфоне за ~30 минут |

## Если что-то сломалось

См. [../troubleshooting.md](../troubleshooting.md) в корне kit'а. Search by error message — там common failures из всех hack/target файлов consolidated в одно место.

## What's NOT in setup

- **SwiftUI basics** — Apple docs
- **Docker basics** — Docker docs
- **OAuth 2.0 theory** — RFC 6749 / RFC 8252 / RFC 7636
- **TLSNotary protocol details** — `mobile-app/spec/RESEARCH.md` §1 + tlsnotary.org blog
- **WebAuthn theory** — webauthn.guide или W3C spec

Эти гайды предполагают что ты владеешь fundamentals. Они дают **именно то что нужно для этого проекта**, без обобщений.
