# Research Task v4 — Fastest, Lowest-Friction LOGIN for zkTLS Proving (LOGIN ONLY)

> **Scope reset.** Prior versions drifted into "which proof is worth making." That is **not** the question. This is **login-UX research, full stop.** The only question: how does a user authenticate to a service as fast and painlessly as possible (no typed credentials, fewest taps/seconds) so REP can notarize the session via TLSNotary — **without killing the "connect account" funnel**?
>
> **The deliverable is an adaptive login ROUTER** (a Swiss-army-knife) that picks the fastest viable blade per situation — OAuth-into-the-app where installed; system-browser cookie-reuse where already logged in; passkey where supported; OTP/password only as last resorts. Existing methods, intelligently composed. **The router is the deliverable — not a flat ranking.**

## OUT OF SCOPE (where prior runs went wrong)
❌ Which proof to make / proof value / wow / flex. ❌ Cohorts, tiers, percentiles, badges, payoffs. ❌ Which platforms are good targets / data value. ❌ Data-extraction difficulty (JSON-vs-HTML, where the fact lives). ❌ Ranking anything by proof value.

**The proof is a GIVEN:** *"the user must be authenticated to service X so we can run a TLSNotary session."* The whole job is the least-painful path to authenticated. The **only** proof-adjacent thing in scope: the login must yield a session/token that TLSNotary **proxy mode** can drive a live request with (a *login-compatibility* constraint — Stage 0).

## Operating principles
1. **Login IS the funnel** — every tap/app-switch/typed char is drop-off; optimize in isolation.
2. **No typed credentials in the happy path** — OAuth / cookie-reuse / passkey ≫ OTP ≫ passwords.
3. **Warm beats cold** — if already logged into the service in the system browser, **reuse that session**. Biggest lever; validate first.
4. **Never dead-end an app-switch** — always auto-return via deep link.
5. **Numbers, not adjectives** — taps, seconds, warm/cold, iOS/Android. Measure or cite.

## Reuse (given — do NOT redo)
- v1 infra (proxy ~1–2 s vs MPC ~3–15 s; proxy uses the verifier's IP) in `research/v1/` — **background only**; don't re-benchmark.
- The v2 login matrix (in `research/v1/01-auth-flows.md`) is the **Stage-1 starting point** — verify/refine, don't reinvent.

## Stages & deliverables
- **Stage 0 → `login-00-handoff.md`** — the login→proving **contract** in proxy mode: how the authenticated session reaches the prover (cookie jar? bearer token? live webview session?). The DefCon `--authenticated` path: how is the token supplied to the request? Which login methods satisfy it.
- **Stage 1 → `login-01-catalog.md`** — the mechanism catalog (app-switch OAuth/PKCE, SiwA/Google, system-browser cookie reuse, passkeys, FIDO CDA, QR cross-device, device grant RFC 8628, SMS OTP, email code/magic link, password): taps, seconds (warm/cold), iOS/Android, credential yielded, Stage-0 compatibility — **ranked strictly by friction**.
- **Stage 2 → `login-02-ux-engineering.md`** — the don't-kill-UX mechanics: warm-state detection & cookie reuse; why an isolated `WKWebView` forces re-login vs Safari-backed sessions; auto-return deep links; single-device vs 2-device QR; platform autofill (iOS Security Code AutoFill / passkey conditional UI; Android SMS Retriever / Credential Manager).
- **Stage 3 → `login-03-router.md`** *(centerpiece)* — the adaptive router: explicit **detection-signal → chosen-method** rules + the **fallback ladder** (warm cookie-reuse → one-tap OAuth/passkey → SMS OTP → email code → password). Target-agnostic.
- **Stage 4 → `login-04-recommendation.md`** — the recommended default connect-account flow (+ fallback), screen-by-screen, taps/seconds, warm/cold, iOS/Android, with a measured target (e.g. *warm ≤2 taps / ≤8 s, zero typing*).

## Anti-goals
❌ Don't evaluate/rank/discuss proofs, platforms, cohorts, tiers, data value — delete any such sentence. ❌ Don't turn this into a data-extraction study (only Stage-0 compat). ❌ No typed-credential happy path. ❌ No token-harvesting / remote-auth abuse; explicit consent; auto-return; client-side custody. ✅ Numbers, not adjectives.

## Open questions
1. **Warm-user floor:** already logged into the service in the system browser → notarizable session in **1 tap, zero typing** via cookie reuse? Confirm.
2. **Spotify in the beta:** why did it force an email code — isolated `WKWebView` (no cookie sharing) or no app-switch OAuth? What flips it to one-tap?
3. Per method: does it satisfy the Stage-0 contract? Which are incompatible?
4. **iOS vs Android:** where does the fastest path differ?
5. **Fallback ladder:** when one-tap isn't available, what's next-fastest that still doesn't kill the funnel?
