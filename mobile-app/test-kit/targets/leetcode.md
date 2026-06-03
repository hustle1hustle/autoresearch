# Target. LeetCode

**Why Tier-1.** Solid signal of coding skill. GraphQL JSON endpoint, durable since at least 2020.

**Mode.** **Proxy (conditional).** LeetCode sits behind Cloudflare. Low-volume reads usually pass. Под нагрузкой Turnstile может kick in.

**Source.** `../../02-targets.md` row 4, `../../03-wow-combos.md` §4.

---

## Auth setup

⚠️ **No public OAuth.** Cookie-path только.

**Auth = cookies.** `LEETCODE_SESSION` + `csrftoken` cookies из юзеров активной сессии в Safari / Chrome.

```
1. Open ASWebAuthSession / WKWebView к leetcode.com
2. Если warm — already logged in
3. Capture cookies LEETCODE_SESSION, csrftoken
4. Replay в notarized GraphQL request
```

## Endpoint to notarize

### Single-fact (own user)

```http
POST /graphql HTTP/1.1
Host: leetcode.com
Cookie: LEETCODE_SESSION=xxx; csrftoken=yyy           ← REDACT
Content-Type: application/json
x-csrftoken: yyy                                        ← REDACT

{
  "query": "query { userStatus { isSignedIn username } matchedUser(username: \"<u>\") { submitStatsGlobal { acSubmissionNum { difficulty count } } } userContestRankingInfo(username: \"<u>\") { attendedContestsCount rating globalRanking } }"
}
```

Response:
```json
{
  "data": {
    "userStatus": { "isSignedIn": true, "username": "user_42" },
    "matchedUser": {
      "submitStatsGlobal": {
        "acSubmissionNum": [
          { "difficulty": "All", "count": 487 },
          { "difficulty": "Easy", "count": 245 },
          { "difficulty": "Medium", "count": 198 },
          { "difficulty": "Hard", "count": 44 }
        ]
      }
    },
    "userContestRankingInfo": {
      "attendedContestsCount": 28,
      "rating": 2156,
      "globalRanking": 3421
    }
  }
}
```

`userStatus.username` confirms ownership (тот же юзер чей session — это его proof).

### Public-only (no auth, по username)

Если только handle proof (not ownership):

```http
POST /graphql HTTP/1.1
Host: leetcode.com

{
  "query": "query { matchedUser(username: \"<u>\") { submitStatsGlobal { acSubmissionNum { difficulty count } } } }"
}
```

No cookies needed но also не proves ownership.

## Redaction map

| Region | Action |
|---|---|
| `Cookie:` header | **REDACT entire header value** |
| `x-csrftoken:` header | **REDACT entire header value** |
| Server identity | reveal |
| Request body (GraphQL query) | reveal |
| Response. `userStatus.username` | reveal (for ownership) |
| Response. `matchedUser.submitStatsGlobal.*` | reveal (the claim) |
| Response. `userContestRankingInfo.*` | reveal |

## Expected response shape

~3-8 KB JSON for full query.

## Mode recommendation

**Proxy (conditional).** Per `../../02-targets.md`. Cloudflare can challenge under load.

**MPC fallback.** Если cookie replay fails (IP/UA pinning) или Cloudflare consistently challenges → MPC.

## ToS posture

⚠️ **Grey.** No official consumer API. LeetCode не promotes third-party reads. Could be deprecated. Reclaim community providers exist для LeetCode что suggest okay для community use.

## Cookie replay durability (Open Question Q5)

Specifically test:
1. Юзер логинится в LeetCode Safari → cookies captured
2. Реплая cookies из fresh TLS session
3. Returns valid data или Cloudflare challenge?

LeetCode known to be sensitive к non-browser User-Agent. Recommend setting realistic User-Agent в notarized request:

```http
User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1
```

Это **may or may not** prevent challenges. Document observation.

## Test configuration

```yaml
target: leetcode
mode: proxy
mode_fallback: mpc
auth: cookie_reuse_aswebauthsession  # or inline WKWebView (Reclaim-style)
endpoint:
  method: POST
  host: leetcode.com
  path: /graphql
oauth: null
cookie_capture:
  cookies: [LEETCODE_SESSION, csrftoken]
  capture_method: ios_aswebauthsession_cookies | android_cct_cookies | wkwebview_internal
expected_taps:
  warm_returning: 1  # с Hack 2 (cookie set instead of refresh_token)
  warm_first: 2-3 (iOS) | 1-2 (Android)
  cold: 5-8 (LeetCode login + потенциально 2FA + Cloudflare challenge)
expected_seconds:
  warm_returning: 4-6
  warm_first: 10-15
  cold: 30-60+ (с Cloudflare challenges)
applicable_hacks: [1, 3 iOS, 4, 6]
notes:
  - "Cloudflare may challenge. Use realistic User-Agent. Falling back to MPC mode гарантирует user IP."
  - "Hack 5 may apply if LeetCode adds passkey support (not as of 2026-06)."
  - "Inline WKWebView (Reclaim-style) recommended — best UX, in-app trust required."
```

## Common failures

- **`{ "errors": [{ "message": "User matchedUser must be authenticated" }] }`** — cookies invalid / expired. Re-capture.
- **Cloudflare 403 / "Just a moment..." HTML** — Cloudflare challenge. Switch to MPC mode.
- **`csrftoken` mismatch.** Если ты replay'ишь old `csrftoken` но new session expected — failure. Use same cookies as captured.
- **Rate limit.** ~10 req/min for un-auth, more для authed. Easy to hit под parallel testing.

## Why это валуабле

Distinct signal vs GitHub (real coding under time pressure vs casual). Contest rating особенно strong filter для "competitive coder" persona.

Combined with GitHub + Codeforces — "polyglot expert algorithmist" composite signal.

## What НЕ to use

- **No HTML scrape leetcode.com/u/<username>** — HTML changes часто, Cloudflare blocks.
- **No `leetcode.cn`** — different platform, different API.
- **No `lcus1.leetcode.com`** или other internal domains — not public.
