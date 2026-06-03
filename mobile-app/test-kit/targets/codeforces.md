# Target. Codeforces

**Why Tier-1 (но с caveat).** Public REST API, zero auth, datacenter IP fine. Cheapest possible "wall of small proofs". **Catch.** doesn't prove ownership — нужно nonce-binding.

**Mode.** **Proxy.** Public unauthenticated API.

**Source.** `../../02-targets.md` row 2, `../../03-wow-combos.md` §5.

---

## Auth setup

**No auth needed.** Codeforces public API doesn't require token.

**But.** API returns data о handle, не о specific user. Чтобы prove ownership нужно binding step:

### Identity-bind options

**Option A. Nonce в profile field.**

1. REP issues random nonce e.g. `rep-bind-7a3f9b2c`
2. User updates Codeforces `firstName` или `lastName` field на этом nonce
3. Notarize call returns `firstName` containing nonce
4. REP verifies. nonce matches → handle owned by REP user

**Option B. OAuth-через-другой-target.**

Hacky. но если user authed через GitHub в REP, и его Codeforces handle linked to GitHub email — можем infer ownership. Менее clean.

**Recommended. Option A.** Один extra step, но cryptographically clean.

## Endpoint to notarize

### Public user info

```http
GET /api/user.info?handles=<handle> HTTP/1.1
Host: codeforces.com
```

Response:
```json
{
  "status": "OK",
  "result": [
    {
      "handle": "tourist",
      "rating": 3812,
      "maxRating": 3979,
      "rank": "legendary grandmaster",
      "firstName": "Gennady",  ← может быть nonce здесь для binding
      "lastName": "Korotkevich"
    }
  ]
}
```

### Multi-fact

```
GET /api/user.info?handles=<h>
GET /api/user.rating?handle=<h>           → full rating history
GET /api/user.status?handle=<h>&count=20  → last 20 submissions
```

3 GETs в одной TLS session. Reveal. rating, maxRating, contest history, recent solutions.

## Redaction map

| Region | Action |
|---|---|
| Server identity | reveal |
| Request URLs | reveal |
| Response (all fields) | reveal selectively |

**No auth header to redact** — это public API.

## Expected response shape

- `/user.info`. ~500 bytes per handle
- `/user.rating`. ~5-20 KB (rating history can be long)
- `/user.status?count=20`. ~10-30 KB (submission details)

Total transcript ~30-50 KB. Easily handles in proxy mode (`max_recv_data = 64 KB`).

## Mode recommendation

**Proxy.** `codeforces.com/api` is public, не IP-blocked.

**MPC.** Не expected to need.

## ToS posture

✅ **Clean.** Public documented API ([apiHelp/methods](https://codeforces.com/apiHelp/methods)). Encouraged для third-party integration.

## Identity binding workflow

```
1. REP user wants to prove Codeforces handle ownership
2. REP generates nonce: rep-bind-7a3f9b2c-2026
3. REP shows instructions: "Update your Codeforces firstName to 'rep-bind-7a3f9b2c-2026' (you can change back after)"
4. User updates profile в Codeforces
5. User tap "I've updated it" в REP
6. REP fires GET /api/user.info?handles=<handle>
7. Notarize transcript. attestation includes firstName field
8. Verify. firstName contains nonce → handle owned by REP user
9. Optional. user changes firstName back. Proof remains valid.
```

This adds ~30-60 seconds to the cold flow (manual profile update), но cheaper than OAuth.

## Test configuration

```yaml
target: codeforces
mode: proxy
auth: nonce_binding
endpoint:
  method: GET
  host: codeforces.com
  paths:
    - /api/user.info?handles=<h>
    - /api/user.rating?handle=<h>
    - /api/user.status?handle=<h>&count=20
oauth: null
nonce_binding:
  field: firstName  # or lastName
  format: "rep-bind-<8 hex chars>-<year>"
  instruction_copy: "Update your firstName on Codeforces to bind your handle"
expected_taps:
  warm_returning: 1
  warm_first_no_binding: 1
  cold_with_binding: 4-6 (включая update profile)
expected_seconds:
  warm_returning: 3-5
  warm_first_no_binding: 5-8
  cold_with_binding: 60-90 (manual profile edit)
applicable_hacks: [1, 4, 6]
notes:
  - "Hack 2 не нужен — no OAuth token to cache. Faster on repeat."
  - "Hack 3 не нужен — no scary system sheet."
  - "Hack 5 не применим — no passkey."
  - "Cheapest single-fact proof in Tier-1."
```

## Common failures

- **Handle doesn't exist.** API returns `status: FAILED`. Handle bad pattern.
- **`comment` field for binding instead of `firstName`.** Codeforces разрешает только firstName / lastName / country / city / organization для binding. NO 'bio' field publicly.
- **Rate limit.** ~5 req/sec. Не a concern для single user, но parallel testing — throttle.

## Why это валуабле

GitHub - competitor's territory. У GitHub OAuth есть. Codeforces - unique signal что нельзя easily fake. Skilled-dev marker особенно сильный для competitive programming community.

REP может market "Prove your Codeforces rating in 1 tap" как unique value vs Reclaim / Primus которые сосредоточены на cookie-path / OAuth targets.

## What НЕ to use

- **No screen scrape on codeforces.com/profile/<handle>** — HTML changes. Stick API.
- **No `acmsguru.com` / mirrors** — not authoritative, can show stale data.
- **No "Verified by Codeforces"** — Codeforces doesn't offer Verified User Badge API. Verified-by-REP только.
