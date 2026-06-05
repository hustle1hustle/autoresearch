# Target. Strava

**Why Tier-1.** Clean OAuth JSON, Reclaim-proven (ships "Last 4 Weeks Activities" provider). Auth-friction main knock — mobile OAuth handoff документирован как clunky ([Strava communityhub](https://communityhub.strava.com/developers-api-7/use-strava-app-for-oauth2-authorization-from-web-9992)).

**Mode.** **Proxy.** `api.strava.com` standard OAuth API, datacenter IP проходит.

**Source.** `../../02-targets.md` row 5, `../../03-wow-combos.md` §3.

---

## OAuth setup

### Step 1. Create Strava API App

1. https://www.strava.com/settings/api → Create App
2. **Application Name.** REP (test)
3. **Category.** "Other"
4. **Website.** https://r3p.xyz
5. **Authorization Callback Domain.** `r3p.xyz`  
   ⚠️ Strava accepts only domain, не full path
6. **Allowed scopes.** `activity:read` (или `activity:read_all` для richer data)

### Step 2. Note credentials

- Client ID, Client Secret. server-side
- Refresh tokens enabled by default в Strava

### Step 3. Mobile deep link (preferred)

```swift
let authURL = "strava://oauth/mobile/authorize" +
    "?client_id=\(clientID)" +
    "&redirect_uri=https://r3p.xyz/oauth/strava/callback" +
    "&response_type=code" +
    "&approval_prompt=auto" +
    "&scope=activity:read" +
    "&code_challenge=\(pkce.challenge)" +
    "&code_challenge_method=S256"

if UIApplication.shared.canOpenURL(URL(string: "strava://")!) {
    UIApplication.shared.open(URL(string: authURL)!)
} else {
    // fallback to web OAuth
    fallbackToWebOAuth()
}
```

`strava://oauth/mobile/authorize` app-switches в Strava app если установлена → лучший UX (warm path).

### Step 4. Web fallback

Если Strava app не установлена:

```
https://www.strava.com/oauth/mobile/authorize?...
```

Это loads в ASWebAuthSession. Strava сам redirect'нит на actual login if needed.

## Endpoint to notarize (single-fact)

### Lifetime stats

```http
GET /api/v3/athlete HTTP/1.1
Host: www.strava.com
Authorization: Bearer xxx          ← REDACT
```

Response:
```json
{
  "id": 12345,
  "username": "runner_42",
  "firstname": "Jane",
  "lastname": "Doe",
  ...
}
```

Reveal. `id`, `username`. Redact bearer.

## Multi-endpoint variant (recommended для rich proof)

Single TLS session, batch 4 endpoints, ~2-3s notarize:

```
GET /api/v3/athlete                              → identity
GET /api/v3/athlete/stats?id=<id>                → lifetime totals
GET /api/v3/athlete/activities?after=<ts>&per_page=30  → recent activities
GET /api/v3/athlete/zones                        → HR zones
```

Reveal map для composite. user id, total runs/distance, last 30 days stats, heart-rate zones.

## Redaction map

| Region | Action |
|---|---|
| `Authorization: Bearer <token>` × 4 requests | **REDACT all 4** |
| Server identity | reveal |
| All request paths + headers (кроме auth) | reveal |
| Response. desired fields | reveal selectively |
| Response. user's email, address, phone if present | redact (privacy) |

## Expected response shape

- `/athlete`. ~300 bytes
- `/athlete/stats`. ~500 bytes
- `/athlete/activities?per_page=30`. ~5-15 KB
- `/athlete/zones`. ~200 bytes

Total transcript ~20 KB. Easy для proxy mode (flat по payload per `../../00-tlsnotary.md` §6).

## Mode recommendation

**Proxy.** `api.strava.com` token-rate-limited (200/15min, 2000/day per app). No IP blocking.

**MPC fallback.** Не expected. См. Open Question Q5 (`../../open-questions.md`) если сталкиваешься с unexpected blocks.

## ToS posture

✅ **Clean.** Documented public API. Per developer agreement, OK для third-party reads.

## Test configuration

```yaml
target: strava
mode: proxy
auth: oauth_deep_link  # primary, with web fallback
endpoint:
  method: GET
  host: www.strava.com  # API is on this host
  paths:
    - /api/v3/athlete
    - /api/v3/athlete/stats
    - /api/v3/athlete/activities
    - /api/v3/athlete/zones
oauth:
  authorize_url: strava://oauth/mobile/authorize  # deep link
  authorize_url_web: https://www.strava.com/oauth/mobile/authorize
  token_url: https://www.strava.com/oauth/token
  refresh_url: https://www.strava.com/oauth/token  # same endpoint with refresh grant
  scope: activity:read
  pkce: true
expected_taps:
  warm_returning: 1
  warm_first: 3-4
  cold: 5-7
expected_seconds:
  warm_returning: 4-5
  warm_first: 10-15
  cold: 30-45
applicable_hacks: [1, 2, 3, 4, 6]
notes:
  - "Mobile OAuth UX documented as clunky. invest in polished native handoff."
  - "Sign in with Google/Apple can spawn duplicate accounts. avoid."
```

## Common failures

- **Strava app open'ит web view instead of native.** Bug на Strava side для some users. Document and fall back.
- **Token endpoint 400 на refresh.** Verify refresh grant uses `grant_type=refresh_token`, не `authorization_code`.
- **Scope insufficient.** `activity:read` vs `activity:read_all` — `_all` нужен для частных activities. Use `activity:read` если ты ОК на public-only.
- **OAuth scope mismatch.** GitHub-style scope drift. Verify expected response fields доступны со scope which ты requested.

## "Sign in with Google" trap

Strava позволяет sign in via Google. Если юзер делал Strava registration via Google, его Strava account linked to Google. На re-OAuth через email auth Strava может создать **новый** account вместо existing.

Fix. В pre-sheet warn юзера. "If you signed up для Strava through Google, tap Continue with Google в Strava sign-in" — нет magic решения, юзер должен использовать тот же auth method что и при registration.
