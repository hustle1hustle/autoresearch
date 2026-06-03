# Target. Stack Overflow

**Why Tier-1.** Clean OAuth для `/me`, или public reads для `/users/{id}`. Stable JSON API since 2013 (v2.x). CC-licensed data.

**Mode.** **Proxy.** `api.stackexchange.com` public/OAuth API, datacenter IP fine.

**Source.** `../../02-targets.md` row 3, `../../03-wow-combos.md` §6.

---

## OAuth setup

### Step 1. Register Stack Apps app

1. https://stackapps.com/apps/oauth/register
2. **Application Name.** REP
3. **Application Website.** https://rep.xyz
4. **OAuth Domain.** rep.xyz
5. **Application Use.** End-user — Consumer application
6. **Enable Client Side OAuth Flow** для PKCE
7. Note Client ID, Client Secret, Application Key

### Step 2. PKCE setup

```swift
let authURL = "https://stackoverflow.com/oauth" +
    "?client_id=\(clientID)" +
    "&scope=read_inbox" +    // request only read scope
    "&redirect_uri=https://rep.xyz/oauth/stackoverflow/callback" +
    "&state=\(state)" +
    "&code_challenge=\(pkce.challenge)" +
    "&code_challenge_method=S256"
```

## Endpoint to notarize

### Authed `/me` (ownership-bound)

```http
GET /2.3/me?site=stackoverflow&access_token=<token>&key=<app_key> HTTP/1.1
Host: api.stackexchange.com
Accept-Encoding: identity     ← важно. SE gzips, prover должен handle
```

Response (gzipped by default, force identity для simpler):
```json
{
  "items": [
    {
      "badge_counts": { "bronze": 50, "silver": 12, "gold": 1 },
      "account_id": 12345,
      "is_employee": false,
      "user_id": 67890,
      "reputation": 8475,
      "display_name": "user_42"
    }
  ],
  "has_more": false,
  "quota_max": 10000,
  "quota_remaining": 9999
}
```

### Public по user_id (no auth, no ownership)

```http
GET /2.3/users/<user_id>?site=stackoverflow HTTP/1.1
Host: api.stackexchange.com
Accept-Encoding: identity
```

Same response shape (без OAuth-only fields).

### Multi-fact

```
GET /2.3/me?site=stackoverflow&access_token=...&key=...
GET /2.3/me/answers?site=stackoverflow&pagesize=10&access_token=...&key=...
GET /2.3/me/tags?site=stackoverflow&pagesize=10&access_token=...&key=...
```

Reveal. reputation, badges, last 10 answers (id + score), top 10 tags.

## Redaction map

⚠️ **Tricky.** `access_token` и `key` в URL query, не header.

| Region | Action |
|---|---|
| Server identity | reveal |
| Request path `/2.3/me` | reveal |
| Request query `?site=stackoverflow` | reveal |
| Request query `&access_token=<token>` | **REDACT** the token value substring |
| Request query `&key=<key>` | **REDACT** the key value substring |
| Response body | reveal |

Reveal map нужно работать с byte ranges. reveal bytes before `access_token=`, REDACT bytes inside `access_token=...`, reveal `&key=`, REDACT key value, reveal rest.

Это more complex чем header-based redaction. Если возможно — switch на header auth:

```http
GET /2.3/me?site=stackoverflow&key=<key> HTTP/1.1
Authorization: Bearer <access_token>
```

⚠️ **Verify.** StackExchange API supports header bearer auth? [Check current docs](https://api.stackexchange.com/docs). Если да — используй header вместо query. Cleaner redaction.

## Expected response shape

- `/me`. ~500-2000 bytes
- `/me/answers?pagesize=10`. ~3-10 KB
- `/me/tags?pagesize=10`. ~2-5 KB

Total ~15-20 KB. Easy proxy mode.

## Mode recommendation

**Proxy.** `api.stackexchange.com` standard rate-limited API.

## ToS posture

✅ **Clean.** CC-licensed data, official API.

## Test configuration

```yaml
target: stackoverflow
mode: proxy
auth: oauth_pkce  # for ownership; public for handle-only
endpoint:
  method: GET
  host: api.stackexchange.com
  paths:
    - /2.3/me                      # ownership
    - /2.3/me/answers              # rich profile
    - /2.3/me/tags                 # expertise areas
  query_redaction:
    - access_token
    - key
oauth:
  authorize_url: https://stackoverflow.com/oauth
  token_url: https://stackoverflow.com/oauth/access_token
  scope: read_inbox
  pkce: true
expected_taps:
  warm_returning: 1
  warm_first: 2-3
  cold: 4-5
expected_seconds:
  warm_returning: 3-4
  warm_first: 8-12
  cold: 25-35
applicable_hacks: [1, 2, 3, 4, 6]
notes:
  - "API уses gzip by default. Set Accept-Encoding: identity to simplify proof."
  - "OAuth flow uses query-string token, not header (legacy). Redaction trickier than header path."
  - "Hack 5 не применим (no passkey on Stack Apps OAuth)."
```

## Common failures

- **`error_id: 400, error_name: bad_parameter`** — usually missing `site=stackoverflow` parameter. Required.
- **`quota_remaining: 0`** — daily 10K limit. Reset at midnight UTC.
- **Gzip parse error в prover.** Если ты не отключил gzip (`Accept-Encoding: identity`) и prover не decompress'ит — proof transcript содержит binary. Redaction breaks.
- **OAuth не возвращает refresh_token.** Stack Apps OAuth tokens have no expiration по default. `expires_on_never`. Так что Hack 2 модифицирован — сохраняем access_token directly (он не expires).

## Why это валуабле

Stack Overflow reputation особенно сильный signal "expert in technology X". Для REP это компонент "is_expert(topic)" predicate.

Stack Overflow tags reveal что юзер знает (last 10 most-active tags). Это rich context для AI agents выбирающих кому assign задачу.

## What НЕ to use

- **No HTML scrape stackoverflow.com/users/<id>** — HTML rerenders, breaks.
- **No `/me/inbox` endpoint** — privacy-sensitive, not useful для public proof.
- **No data dump (`data.stackexchange.com`)** — это batch SQL, не realtime API.
