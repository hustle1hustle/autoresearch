# Target. GitHub — HERO

**Why hero.** Cleanest path. in-scope plain bearer OAuth, stable JSON GraphQL since 2016, clean ToS, proxy-safe (datacenter IP fine на `api.github.com`), Reclaim-proven, audience = REP's seed users (devs).

**Mode.** **Proxy.** `api.github.com` token-rate-limited, не IP-flagged. Per `../../02-targets.md` row 1 + `../../ROUTING.md` Level 1.

**Source files.** `../../04-hero-flow.md` (full Rust skeleton), `../../03-wow-combos.md` §1.

---

## OAuth setup

### Step 1. Create GitHub OAuth App

1. https://github.com/settings/developers → New OAuth App
2. **Name.** REP (test)
3. **Homepage URL.** https://r3p.xyz
4. **Authorization callback URL.** `https://r3p.xyz/oauth/github/callback`  
   ⚠️ HTTPS, не custom scheme. Required for Universal Link auto-return (Hack 4).
5. **Enable refresh tokens.** В OAuth App settings включи "Issue refresh tokens" чтобы получить refresh_token в response. ([GitHub docs](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/refreshing-user-access-tokens))

### Step 2. Note credentials

- Client ID. `<from settings>`
- Client Secret. server-side only, не bundle в mobile app
- Scopes requested. `read:user`

### Step 3. PKCE

```swift
let pkce = PKCE.generate()
// codeVerifier — 43-128 char base64url string
// codeChallenge — SHA256(codeVerifier), base64url encoded
let authURL = "https://github.com/login/oauth/authorize" +
    "?client_id=\(clientID)" +
    "&redirect_uri=https://r3p.xyz/oauth/github/callback" +
    "&scope=read:user" +
    "&code_challenge=\(pkce.challenge)" +
    "&code_challenge_method=S256" +
    "&state=\(randomState)"
```

## Endpoint to notarize

### Request

```http
POST /graphql HTTP/1.1
Host: api.github.com
User-Agent: rep-prover/1.0
Authorization: Bearer gho_xxxxxxxxxxxxxxxxxxxx          ← REDACT
Accept: application/json
Content-Type: application/json
Content-Length: <n>
Connection: close

{
  "query": "query { viewer { login contributionsCollection(from: \"2026-01-01T00:00:00Z\") { contributionCalendar { totalContributions } } } }"
}
```

### Response (revealed in proof)

```json
{
  "data": {
    "viewer": {
      "login": "octocat",
      "contributionsCollection": {
        "contributionCalendar": {
          "totalContributions": 1234
        }
      }
    }
  }
}
```

## Redaction map

| Transcript region | Action | Why |
|---|---|---|
| TLS server identity (`api.github.com` cert/SNI) | **reveal** | binds claim к GitHub |
| Request line + `Host` + GraphQL query body | **reveal** | verifier должен видеть что было asked |
| `Authorization: Bearer <token>` value | **REDACT** | reveal bytes до/после, hide token |
| Response `login` + `totalContributions` | **reveal** | the claim |
| Other response bytes | optional redact | minimize disclosure |

Reference. `../../04-hero-flow.md` §2 для exact reveal/redact code в Rust prover skeleton.

## Expected response shape

Median size response ~200 bytes. Max ~500 bytes для richer query (с repositories sub-field, etc).

## Mode recommendation

**Proxy.** Подтверждено в `../../02-targets.md`. `api.github.com` rate-limit 5000 req/hr **per token**, не per IP. Datacenter IP from verifier OK.

**MPC fallback.** Только если в редком случае GitHub WAF challenges нашего verifier IP (что не должно случиться для официального API). См. `../../ROUTING.md` Level 1 mode routing.

## ToS posture

✅ **Clean.** Official GraphQL API documented, encouraged for third-party integrations. `read:user` scope explicitly документирован для contribution data ([discussion #77967](https://github.com/orgs/community/discussions/77967)).

## Multi-endpoint variant (Size 2)

Если хочешь kitchen-sink GitHub proof, batch более fields в **одном** GraphQL query:

```graphql
query {
  viewer {
    login
    name
    bio
    contributionsCollection(from: "2026-01-01T00:00:00Z") {
      contributionCalendar { totalContributions }
      pullRequestContributions { totalCount }
      issueContributions { totalCount }
      commitContributionsByRepository(maxRepositories: 5) {
        repository { nameWithOwner }
        contributions { totalCount }
      }
    }
    repositories(first: 5, orderBy: {field: STARGAZERS, direction: DESC}) {
      nodes { nameWithOwner stargazerCount primaryLanguage { name } }
    }
    followers { totalCount }
  }
}
```

Один TLS request, один response, один attestation. ~1-2 секунды notarize (GraphQL batching без overhead). Per `../../mobile-ux-deep-research.md` §"Size 2" (multi-endpoint).

## Test configuration для kit

```yaml
target: github
mode: proxy
auth: oauth_app_switch  # or web_browser fallback
endpoint:
  method: POST
  host: api.github.com
  path: /graphql
oauth:
  authorize_url: https://github.com/login/oauth/authorize
  token_url: https://github.com/login/oauth/access_token
  refresh_url: https://github.com/login/oauth/access_token
  scope: read:user
  pkce: true
expected_taps:
  warm_returning: 1   # с Hack 2
  warm_first: 2-3
  cold: 4-5
expected_seconds:
  warm_returning: 3-4
  warm_first: 7-10
  cold: 20-30
applicable_hacks: [1, 2, 3, 4, 5_via_REP_self, 6]
```

## Common failures

- **403 на token exchange.** Probably PKCE mismatch. Verify code_verifier sent matches what generated с code_challenge.
- **Empty contributions.** `from` date в будущем или юзер реально 0 contributions. Sanity check user's GitHub profile.
- **Token expired error mid-notarize.** access_token expired in 8h. Если ты cached больше — refresh first.
- **Rate limit hit.** 5000 req/hr per token. Maximum we'd hit это в parallel tests. Use throttle.
