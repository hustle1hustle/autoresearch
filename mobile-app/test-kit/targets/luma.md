# Target. Luma

**Why Tier-1.** Public API endpoint для personal profile (event_attended_count, event_hosted_count, joined_at). Cookie-path. Strong identity signal для "real human, real community member" persona. Особенно ценно для AI agents и tech-event communities.

**Mode.** **Proxy (conditional).** `api.lu.ma` lightly defended. Datacenter IP usually OK для low-volume reads.

**Source.** [Luma API help docs](https://help.luma.com/p/luma-api) + [zkpass-schemas/luma-event.md](https://github.com/Nith567/zkpass-schemas/blob/main/luma-event.md) (confirms zkTLS-style integration pattern).

---

## Auth setup

⚠️ **No public consumer OAuth.** Luma Plus subscribers получают API keys per calendar, но это для business use. Для consumer-side proof'ов — **cookie reuse**.

Auth = session cookie из юзеров активной сессии в Safari / Chrome на `lu.ma`.

**Cookie path:**
1. ASWebAuthSession (iOS) / Chrome Custom Tab (Android) opens `https://lu.ma/`
2. Если warm — already logged in
3. Capture session cookies (specific names TBD, see Open Question ниже)
4. Replay в notarized request к `api.lu.ma/user/profile`

**Inline WebView (Reclaim-style)** также viable. user логинится прямо в host-shell sheet через WKWebView, credentials остаются client-side.

## Endpoint to notarize

### Single-fact (own profile)

```http
GET /user/profile HTTP/1.1
Host: api.lu.ma
Cookie: <session cookies>           ← REDACT entire header
Accept: application/json
```

Response:
```json
{
  "name": "Jane Doe",
  "avatar_url": "https://...",
  "bio": "...",
  "event_attended_count": 47,
  "event_hosted_count": 3,
  "event_together_count": 12,
  "instagram_handle": "...",
  "linkedin_handle": "...",
  "twitter_handle": "...",
  "timezone": "America/Los_Angeles",
  "joined_at": "2023-04-15T12:30:00Z",
  "last_online_at": "2026-06-03T08:15:00Z"
}
```

## Redaction map

| Region | Action | Why |
|---|---|---|
| `Cookie:` header | **REDACT entire header** | session sensitive |
| Server identity (`api.lu.ma`) | reveal | binds claim к Luma |
| Request path + method | reveal | verifier sees what was asked |
| Response. `event_attended_count`, `event_hosted_count`, `event_together_count` | reveal | the claim |
| Response. `name`, `avatar_url`, social handles | **reveal optional** (depends на user privacy choice) |
| Response. `joined_at` | reveal (it's the privacy "nullifier" per zkpass schema) |
| Response. email, IP, internal IDs | redact (privacy) |

**v1 recommendation.** Reveal только `event_attended_count` + `event_hosted_count` + `joined_at`. Все остальные fields optional via "include identity (name + avatar)" checkbox в success state.

## Expected response shape

~1-3 KB JSON.

## Mode recommendation

**Proxy (conditional).** Per existing zkpass-schemas evidence. Most reads pass.

**MPC fallback.** Если cookie replay fails из-за IP/UA pinning. См. `../open-questions.md` Q5.

## ToS posture

⚠️ **Grey.** Lu.ma не offers public docs для consumer-side third-party reads. API exists, behaves stable, но not explicitly endorsed. Reclaim/zkpass community uses it.

**Low risk** because. (a) endpoint stable since at least 2023, (b) data is юзеров own (not scraping others), (c) similar pattern к Reclaim's Duolingo/LeetCode providers.

## Test configuration

```yaml
target: luma
mode: proxy
mode_fallback: mpc
auth: cookie_reuse_aswebauthsession  # or inline WKWebView
endpoint:
  method: GET
  host: api.lu.ma
  path: /user/profile
oauth: null
cookie_capture:
  cookies: [TBD - see open question]
  capture_method: ios_aswebauthsession_cookies | android_cct_cookies | wkwebview_internal
expected_taps:
  warm_returning: 1-2  # с Hack 2 (cookie set storage analog)
  warm_first: 2-3 (iOS) | 1-2 (Android silent CCT)
  cold: 5-7 (Luma login + потенциально magic-link verification)
expected_seconds:
  warm_returning: 4-6
  warm_first: 8-15 (iOS sheet)
  cold: 30-60+ (magic-link path adds inbox switch — drop risk)
applicable_hacks: [1, 3 iOS, 4, 6]
notes:
  - "Hack 2 модифицирован. сохраняем cookie set вместо OAuth refresh_token."
  - "Hack 5 не применим (no passkey on Luma as of 2026-06)."
  - "Watch: Luma часто использует magic-link для login. cold path может быть painful. Anti-pattern 'Lost in inbox' relevant — user может уйти в Mail и не вернуться. Mitigate. recommend cold user сначала залогиниться в Luma в Safari, потом запустить REP flow."
  - "Multi-event proof возможен через /event/list endpoint (нужен research), но v1 = profile counts only."
```

## Common failures

- **Cookie name unknown.** Need real device test чтобы capture exact session cookie name(s). См. open question ниже.
- **401 на replay.** Cookie IP/UA pinned. Fall back на MPC mode.
- **Magic-link login flow в cold path.** Юзер уходит в inbox для verification link. Высокий risk abandon.
- **Rate limit.** Unknown threshold. Document if encountered.

## Open question specific to Luma (add к open-questions.md)

**OQ-Luma. What are the exact session cookie name(s) used by `lu.ma` / `api.lu.ma`?**

Need real device probe:
1. Login на lu.ma в Safari
2. Inspect cookies через Safari Develop menu → Show Web Inspector → Storage tab
3. Document. cookie name + domain + secure flag + httpOnly flag

Без этого Hack 2 не может работать stable (cookie set нужно знать чтобы persist в Keychain).

## Why это валуабле для REP

Luma proof = "active in real-world tech community". Особенно strong filter для:
- AI startup / tech event audience (overlap с REP seed users)
- "Real human, not bot" baseline (3+ events attended)
- Geographic / timezone signal (без revealing exact location)
- Composability с другими proof'ами. GitHub + Luma = "shipping dev who attends community events" — strong hire signal

## What НЕ to use

- **No HTML scrape lu.ma/<username>** — public pages but HTML changes
- **No /event/<event-id> endpoints для proving "attended specific event"** — requires more research, v2
- **No Plus API keys для consumer flow** — нужны business subscription, не для consumer proofs

## v2 extensions (future)

- **Specific event attendance proof.** "I attended <event-id>." Endpoint TBD (likely `/event/{id}/attendees` или similar). Adds verifiable conference / meetup attendance.
- **Calendar host proof.** "I host calendar <cal-id> с N subscribers." Уже доступно через Plus API endpoint, но требует pasting key (как Anthropic flow).
- **Multi-event aggregation.** Notarize `/user/events?limit=20` + composite proof "attended 5+ events in category X" via post-processing.
