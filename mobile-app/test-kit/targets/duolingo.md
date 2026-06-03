# Target. Duolingo

**Why Tier-1.** Durable unofficial JSON (`/2017-06-30/` version stable 6+ years). Reclaim-proven (ships "Verify totalXp" provider). High virality (streak як social signal).

**Mode.** **Proxy (conditional).** `www.duolingo.com` lightly defended. Datacenter IP usually OK для low-volume reads. Watch для rate-limit / Turnstile под нагрузкой.

**Source.** `../../02-targets.md` row 6, `../../03-wow-combos.md` §2.

---

## Auth setup

⚠️ **No public OAuth.** Duolingo не offers third-party API. Auth = **cookie reuse** через `jwt_token` cookie из юзеров активной сессии в Safari / Chrome.

Cookie capture path:
1. ASWebAuthSession (iOS) / Chrome Custom Tab (Android) opens `https://www.duolingo.com/`
2. Если юзер залогинен → cookie `jwt_token` shared
3. Host-shell captures cookie через WKHTTPCookieStore (iOS) / CookieManager (Android)
4. Реплая cookie в notarized request

**Inline WebView подход (Reclaim-style).** Open WKWebView inside host-shell sheet, юзер логинится прямо в твоём sheet. Capture cookie internally. Pattern from Reclaim ([security FAQ](https://blog.reclaimprotocol.org/posts/security-faq)).

## Endpoint to notarize

### Single-fact

```http
GET /2017-06-30/users/<user_id>?fields=streak,totalXp,username HTTP/1.1
Host: www.duolingo.com
Cookie: jwt_token=<token>           ← REDACT entire Cookie header
```

Response:
```json
{
  "streak": 365,
  "totalXp": 98765,
  "username": "user_42"
}
```

User ID можно resolve через `https://www.duolingo.com/2017-06-30/users?username=<username>` если знаем username, или через session info.

### Multi-fact

```
GET /2017-06-30/users/<id>?fields=streak,totalXp,courses,leagueRank,id,username
```

Один запрос, multiple fields через field-selection (Duolingo поддерживает GraphQL-style `?fields=`).

## Redaction map

| Region | Action |
|---|---|
| `Cookie: jwt_token=...` | **REDACT entire Cookie header** |
| Server identity, path, query | reveal |
| Response. `streak`, `totalXp`, `username`, etc | reveal |
| Response. `email`, `profile_picture_url`, etc | redact (privacy) |

## Expected response shape

~2-5 KB JSON depending на fields requested.

## Mode recommendation

**Proxy (conditional).** Per `../../02-targets.md`. Most reads pass. Под нагрузкой Cloudflare Turnstile может kick in.

**MPC fallback.** Если cookie replay fails из-за IP/UA pinning. См. Open Question Q5.

## ToS posture

⚠️ **Grey.** Unofficial API. Has been stable 6+ years and Reclaim ships provider, so low immediate risk. **Not for high-stakes products.**

## Cookie replay durability (Open Question Q5)

Test specifically:
1. Юзер логинится в Duolingo Safari → cookie captured
2. Реплая cookie из **fresh TLS session** of host-shell prover
3. Does endpoint return valid JSON или 401?

If 401. cookie IP/UA pinned. Mitigation. MPC mode (user device makes the connection).

## Test configuration

```yaml
target: duolingo
mode: proxy
mode_fallback: mpc  # if cookie replay fails
auth: cookie_reuse_aswebauthsession
endpoint:
  method: GET
  host: www.duolingo.com
  path: /2017-06-30/users/<id>
  query: fields=streak,totalXp,username
oauth: null  # cookie-path
cookie_capture:
  cookies: [jwt_token]
  capture_method: ios_aswebauthsession_cookies | android_cct_cookies | wkwebview_internal
expected_taps:
  warm_returning: 1-2  # с Hack 2 (refresh token analog для cookie)
  warm_first: 2-3 (iOS) | 1-2 (Android silent CCT)
  cold: 4-6 (включая Duolingo login + потенциально 2FA)
expected_seconds:
  warm_returning: 4-5
  warm_first: 7-12 (iOS sheet)
  cold: 25-45
applicable_hacks: [1, 3 iOS, 4, 6]
notes:
  - "Hack 2 модифицирован. сохраняем cookie set вместо refresh_token. Cookie может expire — watch sliding rotation."
  - "Inline WebView (Reclaim-style) — best UX но требует trust в host-shell."
  - "Hack 5 не применим (no passkey support on Duolingo as of 2026-06)."
```

## Common failures

- **Cookie expires mid-session.** Duolingo может rotate cookies. На retry juzeru нужно re-login.
- **401 на replay.** Cookie IP/UA pinned. Fall back на MPC mode.
- **GraphQL-style fields parsing.** Если `?fields=streak,totalXp` returns не subset а full object — Duolingo возможно изменил API. Check current behavior.
- **Cloudflare challenge.** Под нагрузкой can trigger Turnstile. Document occurrence rate.

## Inline WebView nuance

Reclaim's pattern. user логинится прямо в SDK sheet (WKWebView controlled by host-shell), credentials и cookies остаются client-side. Trade-off. user типет password внутри **нашего** sheet → требует UX trust.

Mitigations:
- Sheet shows Duolingo URL bar (`https://www.duolingo.com/login`) prominent
- Sheet shows Duolingo brand chrome dominant, REP subtle
- Юзер видит реальный TLS lock icon

См. `../../mobile-ux-deep-research.md` §3 Reclaim teardown для full UX pattern.

## What НЕ to use

- **No public Duolingo OAuth.** Don't try to OAuth.
- **No screen scraping.** HTML changes break проекты. Stick to JSON `/2017-06-30/`.
- **No login.duolingo.com unofficial endpoints.** They change. Use the stable `/2017-06-30/` path.
