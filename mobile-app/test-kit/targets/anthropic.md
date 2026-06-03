# Target. Anthropic Console (Spend)

**Why Tier-1.5 (showcase, не volume driver).** Clean Admin API для real $ spend / token usage. Strong "skin-in-the-game" signal for B2B / AI agent credibility. **Niche audience** (org admins with API keys).

**Mode.** **Proxy.** `api.anthropic.com` datacenter-friendly.

**Source.** `../../02-targets.md` row 7, `../../03-wow-combos.md` §7.

---

## Auth setup

⚠️ **Not consumer flow.** Auth = **admin API key paste** (`sk-ant-admin...`).

```
1. Org admin goes to https://console.anthropic.com/settings/keys
2. Creates Admin Key (требует org admin role)
3. Copy key
4. Paste в REP host-shell
```

REP сохраняет key в Keychain под `.biometryCurrentSet` (как Hack 2 для refresh_token, но это admin key напрямую).

**Alternative.** Session cookie path через console.anthropic.com (the web billing dashboard). Less clean, ToS-grey (no public docs).

## Endpoint to notarize

### Single-fact (current month spend)

```http
GET /v1/organizations/cost_report?starting_at=2026-06-01T00:00:00Z&ending_at=2026-07-01T00:00:00Z HTTP/1.1
Host: api.anthropic.com
x-api-key: sk-ant-admin-xxx          ← REDACT
anthropic-version: 2023-06-01
```

Response:
```json
{
  "data": [
    {
      "starting_at": "2026-06-01T00:00:00Z",
      "ending_at": "2026-06-02T00:00:00Z",
      "amount_in_usd": "23.45",
      "currency": "usd",
      "organization_id": "org_xxx"
    },
    ...
  ],
  "has_more": false
}
```

### Multi-fact

```
GET /v1/organizations/cost_report?starting_at=...&ending_at=...
GET /v1/organizations/usage_report/messages?starting_at=...&ending_at=...
```

Cost breakdown + token usage by model in one TLS session.

## Redaction map

| Region | Action |
|---|---|
| `x-api-key:` header | **REDACT** |
| Server identity | reveal |
| Request path + query | reveal |
| Response. `amount_in_usd`, totals | reveal |
| Response. `organization_id` | reveal partial (e.g. first 6 chars) or redact (depends на privacy) |

## Expected response shape

Cost report. ~2-10 KB depending on date range granularity.

Usage report. ~3-15 KB with model/workspace breakdown.

## Mode recommendation

**Proxy.** `api.anthropic.com` standard datacenter-friendly API.

## ToS posture

✅ **Clean.** Documented Admin API. Org admin doing this on his own data has full right.

## Test configuration

```yaml
target: anthropic
mode: proxy
auth: admin_key_paste
endpoint:
  method: GET
  host: api.anthropic.com
  paths:
    - /v1/organizations/cost_report
    - /v1/organizations/usage_report/messages
  required_headers:
    - x-api-key
    - anthropic-version
oauth: null
admin_key_storage:
  method: keychain_biometry  # similar to Hack 2 refresh_token storage
expected_taps:
  warm_returning: 1     # Face ID + refresh report
  warm_first: 3-5       # key paste + setup
  cold: 5-10            # включая onboarding в Anthropic console для создания key
expected_seconds:
  warm_returning: 4-6
  warm_first_with_key_ready: 10-15
  cold: 5+ минут (если нужно create admin key)
applicable_hacks: [1, 2 (adapted for admin key), 4 (для re-prove flow), 6]
notes:
  - "Not consumer-volume. niche B2B/agent credibility badge."
  - "Admin key creation flow is OUT OF SCOPE для kit'а — assume key ready."
  - "Hack 3 не нужен — no OAuth handoff, не scary sheet."
  - "Hack 5 не применим."
```

## Common failures

- **403 Forbidden.** Юзер дал regular API key (`sk-ant-...`) instead of admin key (`sk-ant-admin-...`). Show clear error: "Use Admin Key, not regular API Key."
- **400 invalid date range.** ISO 8601 strict. Use Z suffix для UTC.
- **`has_more: true`** — pagination. Сейчас kit не batch'ит paginated responses. Document occurrence.
- **Rate limit.** Admin API has its own quota, but unlikely hit за simple test reads.

## Why это валуабле

REP для AI agents. Proof что org spends real $ на Anthropic = credible "actively uses LLMs in production" signal.

Use cases:
- Hiring. "show me devs who spend $X+ on Anthropic" → они actually using LLMs
- B2B partnership. "we're real customers, here's the proof"
- Insurance / lending. real revenue signal

## What НЕ to use

- **No regular API key endpoints (`/v1/messages`)** — что-то personal compute, not aggregate stats.
- **No console.anthropic.com HTML scrape** — HTML changes, ToS grey.
- **No third-party billing aggregators** — not authoritative.

## Admin key UX flow nuance

Юзер pasting admin key — sensitive moment. Host-shell должен:

1. Pre-sheet объясняет. "Paste your Admin Key from console.anthropic.com/settings/keys. We store it on your device only, encrypted with Face ID."
2. Paste UI с visible "Looks like admin key, format OK" check (verify `sk-ant-admin-...` prefix)
3. Test request к `/v1/organizations/cost_report` before saving — verify key works
4. Save to Keychain под `.biometryCurrentSet`
5. Show success. "Key saved. Next time tap Refresh and use Face ID."

Это самый "trust-heavy" momentum в Tier-1. Carefully UX.
