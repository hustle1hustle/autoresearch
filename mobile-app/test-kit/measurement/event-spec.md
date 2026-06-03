# Event Spec — instrumentation for AIO test kit

Single event-type `proofAttempt` с прогрессивно заполняемыми полями. Каждый stage в flow emits sub-event с обновлением state.

**Source.** Полная спецификация в `../../ROUTING.md` § "Measurement plan". Этот файл — практическая applied version с готовыми snippet'ами.

## Event sequence (full happy path)

```
proofAttempt.start
proofAttempt.cta.tap
proofAttempt.presheet.shown                  [if Hack 3 active]
proofAttempt.presheet.continue                [if Hack 3 active]
proofAttempt.webauth.opened
proofAttempt.webauth.systemSheetShown        [iOS only, без Hack 5]
proofAttempt.webauth.systemSheetContinue
proofAttempt.webauth.targetLoginShown        [cold only]
proofAttempt.webauth.consentShown
proofAttempt.webauth.consentApproved
proofAttempt.webauth.universalLinkReturn
proofAttempt.oauth.tokenExchanged
proofAttempt.notarize.websocketConnected     [if Hack 1, ahead of cta.tap timestamp]
proofAttempt.notarize.requestFired
proofAttempt.notarize.responseReceived
proofAttempt.notarize.proofComputed
proofAttempt.success                          [terminal]
proofAttempt.abandon                          [terminal alternative, с lastStage]
proofAttempt.error                            [terminal alternative, с errorCategory]
```

## Common fields на каждом event

```typescript
interface BaseEvent {
  timestamp: number;        // unix ms или relative ms since proofAttempt.start
  attemptId: string;        // UUID, links events to single attempt
  platform: string;         // "github" | "strava" | "duolingo" | ...
  mode: string;             // "proxy" | "mpc"
  appState: string;         // "warm-returning" | "warm-first" | "coldish" | "cold"
  hackVariant: string;      // "stock" | "hack-1" | "hack-2" | ... | "all-stacked"
  device: {
    os: "iOS" | "Android";
    osVersion: string;      // "17.5", "14"
  };
  appVersion: string;
  anonId: string;           // privacy-safe randomized
}
```

## Stage-specific fields

### `proofAttempt.start`

```typescript
{
  ...base,
  entryScreen: "main" | "platform_picker" | "deep_link"
}
```

### `proofAttempt.cta.tap`

```typescript
{
  ...base,
  cta: "connect_github" | "prove_again" | "add_platform"
}
```

### `proofAttempt.presheet.shown` (Hack 3)

```typescript
{
  ...base,
  msSinceCtaTap: number
}
```

### `proofAttempt.webauth.systemSheetShown` (iOS Hack 3 baseline)

```typescript
{
  ...base,
  msSincePresheetContinue: number  // ideally < 200ms
}
```

### `proofAttempt.webauth.universalLinkReturn` (Hack 4)

```typescript
{
  ...base,
  msSinceConsentApproved: number,
  returnMethod: "universal_link" | "custom_scheme" | "manual_back"
}
```

### `proofAttempt.notarize.websocketConnected` (Hack 1)

```typescript
{
  ...base,
  stage: "prewarm" | "on_demand",
  durationMs: number,         // time taken to open WS
  success: boolean
}
```

### `proofAttempt.notarize.responseReceived`

```typescript
{
  ...base,
  msSinceRequestFired: number,
  bytesReceived: number,
  numEndpoints: number        // 1 для single-fact, >1 для multi-endpoint
}
```

### `proofAttempt.success`

```typescript
{
  ...base,
  totalDurationMs: number,
  perceivedDurationMs?: number,  // optional, from user survey
  notarizationsCount: number     // sub-proofs sealed
}
```

### `proofAttempt.abandon`

```typescript
{
  ...base,
  totalDurationMs: number,
  lastStage: string             // "presheet" | "systemSheet" | "targetLogin" | "consent" | "notarize" | etc
}
```

### `proofAttempt.error`

```typescript
{
  ...base,
  errorCategory: "oauth_denied" | "cf_challenge" | "tls_negotiate_fail" | 
                 "network_drop" | "biometric_failed" | "token_revoked" | 
                 "notarize_timeout" | "unknown",
  errorDetail?: string,
  recovered: boolean            // did user retry and succeed within same attempt?
}
```

## Derived metrics (weekly)

Computed from raw events. См. `../../ROUTING.md` Measurement plan table для full list. Top 5:

| Metric | Definition | Target |
|---|---|---|
| `tap_count_warm_returning` | distinct cta+sheet taps from start to success | 1 |
| `time_to_proof_p50_warm_returning` | median(success.totalDurationMs) | ≤ 4 s |
| `system_sheet_continue_rate` | webauth.systemSheetContinue / webauth.systemSheetShown | > 80% |
| `universal_link_return_rate` | webauth.universalLinkReturn (returnMethod=universal_link) / webauth.consentApproved | > 98% |
| `success_rate_per_target` | success / start, grouped by platform | > 85% warm |

## Cohort slices

Always slice by:
- `platform`
- `appState`
- `hackVariant`
- `device.os`
- `mode`

Без cohort slicing aggregate numbers misleading (stock vs Hack-1 на одном target значит больше чем stock vs stock на разных).

## Capture snippets

См.:
- `capture-ios.swift.snippet` — ready-to-paste Swift impl
- `capture-android.kt.snippet` — ready-to-paste Kotlin impl

Эти snippets emit события в local SQLite или к remote analytics endpoint. Choose based on infra.

## Anonymization

- `anonId` = randomized UUID per device, не tied к real identity
- Не logging full URLs (contain access tokens)
- Не logging request bodies для notarize events (contain queries that may have PII)
- Не logging cookie values

Tester можно see его events через debug console — they're for the тester, not для analytics ingestion.

## Replay для analysis

Каждый attempt = sequence of events with shared `attemptId`. Replay:

```
SELECT * FROM events 
WHERE attemptId = 'xxx' 
ORDER BY timestamp
```

Visualizes как timeline. Use для debugging слишком медленных attempt'ов.
