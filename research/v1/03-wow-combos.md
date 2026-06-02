# Stage 3 — The Wow Combos (the answer)

**What this is.** The intersection of Stage 1 (auth flows) × Stage 2 (targets): the **ranked shortlist of launch flows**, each a concrete `(platform × login × proof)` triple, ranked by **wow-per-effort = proof meaningfulness × (1 / friction)**, **low-stakes first**. Friction scores come from `01-auth-flows.md`; endpoint/IP/ToS facts from `02-targets.md`; mode choice from the `00-tlsnotary.md` decision table.

**The unifying insight that makes these "wow."** Every Tier-1 target below exposes its fact on a **token-rate-limited JSON API** (not an IP-reputation WAF). Per Stage 2's "proxy-IP line," those endpoints **tolerate the verifier's datacenter IP** → we get **proxy mode's ~1–2 s, browser-clean proof**. That is the whole magic trick: *clean API + proxy mode = instant proof from inside a web app, nothing extra to host.* The moment a target hides the fact behind Cloudflare/Akamai/DataDome or device attestation, the flow stops being "wow" (forces MPC's ~13 s floor or a residential proxy) — so those are deliberately **not** in the launch set.

**Time notation:** `auth (warm/cold) + notarize`. Notarize = proxy-mode proving, **~1–2 s** for a 1 KB req / 2 KB resp ([benchmarks](https://tlsnotary.org/blog/2026/05/10/blog-proxy-mode/)); confirmed by my own local run (see `00-tlsnotary.md` run log). Auth numbers are from Stage 1 (sourced where possible, else EST).

---

## The ranked shortlist

| # | Combo (platform · login · proof) | Mode | Warm taps / sec (incl. notarize) | Proof value | ToS | Wow-per-effort |
|---|---|---|---|---|---|---|
| **1** | **GitHub · OAuth app-switch (`read:user`) · "≥N contributions in 2026"** | **Proxy** | **2–3 taps / ~7–10 s** | High (dev reputation) | **Clean** | ★★★★★ **HERO** |
| **2** | **Duolingo · system-browser cookie · "streak ≥ X days / total XP ≥ N"** | **Proxy** | 2–3 taps / ~7–12 s (iOS sheet) | Med (habit/identity, viral) | Grey | ★★★★½ |
| **3** | **Strava · OAuth (`activity:read`) · "ran X km / N activities (4 wks)"** | **Proxy** | 3–4 taps / ~10–15 s | High (real-world achievement) | Clean | ★★★★ |
| **4** | **LeetCode · cookie (or public) · "solved ≥ N / contest rating ≥ R"** | **Proxy** (conditional) | 2–3 taps / ~8–12 s | Med (skill) | Grey | ★★★½ |
| **5** | **Codeforces · public + identity-bind · "rating ≥ R"** | **Proxy** | 1–2 taps / ~5–8 s | Med (skill) | **Clean** | ★★★½ |
| **6** | **Stack Overflow · OAuth `/me` (or public) · "reputation ≥ X"** | **Proxy** | 2–3 taps / ~8–12 s | Med (expertise) | **Clean** | ★★★ |
| **7** | **Anthropic Console · Admin key · "API spend ≥ $X / tokens ≥ N"** | **Proxy** | key-paste / ~5–8 s | High ($ skin-in-game) | **Clean** | ★★★ (niche) |

*Deferred / not launch:* **Spotify listening-history** (recently-played) still works via OAuth but the **tier proof is dead** (Feb-2026 `product` removal) and the dev-mode 5-user cap blocks a public product → see Stage 2; ship later as a "fun" proof only, on the grey consumer-token path. Everything in Tier-2/3 (Uber, Amazon, banks, social) is **MPC-or-residential** and **not** a wedge flow.

> **Why GitHub is #1 and not Duolingo:** Duolingo has higher raw virality, but GitHub is the cleanest *and* highest-signal: an **in-scope plain-bearer OAuth token** (redact one header), a **stable JSON GraphQL endpoint since 2016**, **clean ToS**, **proxy-safe**, **Reclaim-proven**, and an audience (developers, AI-agent builders) that *is* REP's seed user. It best demonstrates the Proof-Graph thesis with the least risk. Duolingo is the consumer-virality follow-up (cookie-path friction + grey ToS keep it at #2).

---

## Combo specs

### 1 — GitHub contributions  ·  OAuth app-switch  ·  Proxy  ·  **HERO** {#github}
*(Full implementation spec in `04-hero-flow.md`; summary here.)*

- **User flow (warm dev — has GitHub app or live github.com session):**
  1. Tap **"Prove your GitHub"** → app-switch to GitHub (or `ASWebAuthenticationSession`).
  2. Face ID in GitHub app → (first time only) one consent screen for `read:user` → app-switches back with an auth code. *(returning users: consent auto-skipped — Stage 1 §3.)*
  3. App exchanges code→**bearer token** (PKCE), fires the notarized GraphQL call. **2–3 taps, ~7–10 s** total. **Cold** (must log into GitHub): +1 login sub-flow, +10–30 s.
- **Mode: Proxy.** `api.github.com` is a token-rate-limited API with no behavioral WAF and no datacenter-IP blocking (Stage 2 → "Y"). So the verifier's cloud IP is fine; we keep the ~1–2 s proof and ship it from a web app with nothing extra to host.
- **Exact endpoint notarized:** `POST https://api.github.com/graphql`, body `{"query":"{ viewer { login contributionsCollection(from:\"2026-01-01T00:00:00Z\") { contributionCalendar { totalContributions } } } }"}`, header `Authorization: Bearer <token>`. **JSON** response: `{"data":{"viewer":{"login":"octocat","contributionsCollection":{"contributionCalendar":{"totalContributions":1234}}}}}`.
- **Claim asserted:** *"As of `<date>`, `api.github.com` reported that GitHub user **`login`** has **`totalContributions` = 1234** in 2026."* Using `viewer{}` (not `user(login:)`) binds the fact to the **token holder's own account** → genuine ownership.
- **Redacted:** the `Authorization: Bearer …` header value (reveal everything else, incl. the query and the `login`+`totalContributions` in the response). The `login` is revealed *on purpose* to bind identity; the token never appears in the presentation.
- **Failure modes → mitigation:**
  - *Token sender-constraint (DPoP/mTLS):* N/A — GitHub issues **plain bearer** tokens (Stage 1 §2a). ✓
  - *Scope erosion (a la Spotify):* `contributionsCollection` is core GraphQL, stable since 2016; low risk. Build OAuth→cookie fallback anyway.
  - *Rate limit:* 5,000 req/hr/token — irrelevant for one call.
  - *TLS version:* verify the prover negotiates a TLSNotary-supported suite with `api.github.com` (supports TLS 1.2 + 1.3); pin TLS 1.2 `ECDHE_RSA_AES128_GCM` if the shipped prover requires it (Stage 1 open risk).

### 2 — Duolingo streak / XP  ·  System-browser cookie  ·  Proxy {#duolingo}
- **User flow (warm — logged into duolingo.com on the device):**
  1. Tap **"Prove your streak"** → `ASWebAuthenticationSession` (iOS) / Chrome Custom Tab (Android) opens duolingo.com.
  2. **iOS:** one "…wants to use *duolingo.com* to Sign In" sheet → Continue (cookie reuse). **Android:** silent (CCT shares Chrome's cookie jar — Stage 1). The extension/prover captures the `jwt_token` cookie and fires the notarized call. **2–3 taps, ~7–12 s** (iOS sheet adds friction). **Cold:** must log into Duolingo web first (+15–40 s; the app-only user is the common cold case here).
- **Mode: Proxy (conditional).** `www.duolingo.com/2017-06-30/*` is lightly defended; datacenter IP passes for low-volume reads. Watch for rate-limit/Turnstile under load → flip to MPC if flagged.
- **Exact endpoint notarized:** `GET https://www.duolingo.com/2017-06-30/users/{id}?fields=streak,totalXp,username` (resolve `{id}` from the session, or via `…/users?username={u}`). **JSON:** `{"streak":365,"totalXp":98765,"username":"…"}`.
- **Claim asserted:** *"`duolingo.com` reported user **`username`** has **streak = 365** (and **totalXp = 98765**) on `<date>`."*
- **Redacted:** the `jwt_token` (and any `Cookie`) header; reveal `streak`/`totalXp`/`username`.
- **Failure modes → mitigation:**
  - *Unofficial API (ToS grey):* the `/2017-06-30/` endpoint has been stable **6+ years** and Reclaim ships a Duolingo provider — low breakage risk, but it's grey ToS → keep it a low-stakes "fun" proof, never a core dependency, and watch for deprecation.
  - *Cookie replay rejection (UA/IP/rotation):* test replay from the new TLS session; if the cookie is IP- or UA-pinned, fall back to MPC (user IP) or capture+replay UA too.
  - *iOS sheet drop-off:* unavoidable for cookie reuse on iOS; mitigate with a pre-sheet explainer ("we'll open Duolingo to read your streak — your login stays on your device").

### 3 — Strava activities  ·  OAuth  ·  Proxy {#strava}
- **User flow (warm):** Tap **"Prove your training"** → deep-link `https://www.strava.com/oauth/mobile/authorize` app-switches into the Strava app → approve `activity:read` → back with code→**bearer**. **3–4 taps, ~10–15 s** (Strava's mobile OAuth is documented as clunky — Stage 2). **Cold:** +Strava login.
- **Mode: Proxy.** `api.strava.com` is a standard OAuth API; datacenter IP passes (Stage 2 → "Y"); Reclaim-proven ("Last 4 Weeks Activities").
- **Exact endpoint notarized:** `GET https://www.strava.com/api/v3/athlete` (profile/id) and/or `GET https://www.strava.com/api/v3/athlete/activities?after=<ts>` → **JSON** array of activities (distance, moving_time, type).
- **Claim asserted:** *"Strava athlete **`id`** logged **N activities / `Σ distance` km** in the last 4 weeks (as of `<date>`)."*
- **Redacted:** `Authorization: Bearer …`; reveal the chosen stats. (Consider revealing only aggregates, not GPS/start points — privacy.)
- **Failure modes → mitigation:** plain bearer ✓ (no DPoP); rate-limit 200/15min irrelevant; main risk is **OAuth UX friction** → invest in a polished native handoff and a "Sign in with Strava" button that avoids the Google/Apple duplicate-account trap (Stage 2).

### 4 — LeetCode solved / contest rating  ·  cookie (or public)  ·  Proxy (conditional) {#leetcode}
- **User flow (warm):** Tap **"Prove your LeetCode"** → system-browser to leetcode.com (cookie reuse, `LEETCODE_SESSION`+`csrftoken`) → notarize. **2–3 taps, ~8–12 s.** Public-profile reads need *no* auth (drop to ~5 s) but don't prove ownership.
- **Mode: Proxy (conditional).** LeetCode is behind Cloudflare; low-volume datacenter reads usually pass but can hit Turnstile under load → MPC fallback.
- **Exact endpoint notarized:** `POST https://leetcode.com/graphql`, `matchedUser{ submitStatsGlobal{ acSubmissionNum{ difficulty count } } }` and `userContestRankingInfo{ rating globalRanking attendedContestsCount }`. **JSON.**
- **Claim asserted:** *"LeetCode user **`username`** has solved **N** problems (contest rating **R**) as of `<date>`."*
- **Redacted:** `Cookie` header; reveal counts/rating + username.
- **Failure modes → mitigation:** GraphQL schema drift (medium) → JSON still beats HTML; **ownership** — for "your" stats notarize the authenticated session call, not the public-by-username one; Cloudflare Turnstile → MPC fallback or accept conditional.

### 5 — Codeforces rating  ·  public + identity-bind  ·  Proxy {#codeforces}
- **User flow:** **No auth needed.** Tap **"Prove your Codeforces"** → notarize a public API call. **1–2 taps, ~5–8 s** — the *fastest* combo. But it proves a fact about a **handle**, not that the user owns it.
- **Mode: Proxy.** `codeforces.com/api` is a public REST API → datacenter IP fine.
- **Exact endpoint notarized:** `GET https://codeforces.com/api/user.info?handles={handle}` → **JSON** `result[0].rating`, `maxRating`, `rank`.
- **Claim asserted:** *"Codeforces handle **`handle`** has rating **R** (max **Rmax**, rank `rank`) as of `<date>`."*
- **Redacted:** nothing sensitive (public call). **Ownership binding (required):** pair with a cheap ownership proof — e.g., the user puts a REP-issued nonce in their Codeforces profile/`firstName`, and we notarize that field in the same/another call → binds `handle → REP identity`. Without binding, this is a *claim about a handle*, not the user.
- **Failure modes → mitigation:** ownership (handled by nonce-binding above); otherwise extremely stable/clean. Great "wall of small proofs" filler.

### 6 — Stack Overflow reputation  ·  OAuth `/me` (or public)  ·  Proxy {#stackoverflow}
- **User flow (warm):** Tap **"Prove your Stack Overflow"** → for ownership, OAuth → bearer → notarize `/2.3/me`. **2–3 taps, ~8–12 s.** Public `/users/{id}` is no-auth (~5 s) but, like Codeforces, proves a fact about an account id, not ownership.
- **Mode: Proxy.** `api.stackexchange.com` is a clean public/OAuth API → datacenter IP fine.
- **Exact endpoint notarized:** `GET https://api.stackexchange.com/2.3/me?site=stackoverflow&access_token=…&key=…` → **JSON** `items[0].reputation`, `badge_counts{gold,silver,bronze}`. (Note: SE gzips responses — the prover must handle/decompress before reveal, or reveal the gzipped bytes + prove decompression; simplest is `Accept-Encoding: identity`.)
- **Claim asserted:** *"Stack Overflow user **`user_id`** has reputation **X** (badges g/s/b) as of `<date>`."*
- **Redacted:** `access_token`/`key` query params (redact the token range; reveal the rest) — note: with token in the URL, reveal the path up to and after the token, not the token itself.
- **Failure modes → mitigation:** token-in-querystring redaction is fiddly (prefer header auth where possible); gzip handling (`Accept-Encoding: identity`); ownership via `/me`. Clean ToS (CC-licensed API).

### 7 — Anthropic Console spend  ·  Admin key  ·  Proxy  ·  *credibility showcase* {#anthropic}
- **User flow:** Org admin pastes an Admin key (`sk-ant-admin…`) → notarize. **No taps for a normal consumer; this is an admin action.** ~5–8 s once the key is in hand.
- **Mode: Proxy.** `api.anthropic.com` is a datacenter-friendly API → IP fine; clean ToS.
- **Exact endpoint notarized:** `GET https://api.anthropic.com/v1/organizations/cost_report` (USD) / `…/usage_report/messages` (tokens), header `x-api-key: sk-ant-admin…`. **JSON.**
- **Claim asserted:** *"Anthropic org reported **$X spend / N tokens** over `<window>` as of `<date>`."* (Strong "skin-in-the-game"/real-usage signal.)
- **Redacted:** `x-api-key` header; reveal the spend/usage figures.
- **Failure modes → mitigation:** **admin-key friction** kills mass "wow" → position as a **B2B/agent credibility badge**, not a consumer flow; small population. The lower-friction `console.anthropic.com` cookie path exists but is grey/unenumerated (Stage 2) — prefer the documented Admin API.

---

## Cross-cutting failure modes & the mitigation policy

| Risk (from Stages 1–2) | Where it bites | Mitigation in the launch set |
|---|---|---|
| **Proxy verifier-IP flagged** | none of the Tier-1 set (all token-rate-limited APIs) | keep launch set to clean APIs; **auto-flip to MPC** (user IP) if a target starts WAF-challenging the verifier |
| **DPoP/mTLS sender-constrained tokens** | banks, health, **Bluesky** — *not* in launch set | avoid for the wedge; all 7 combos use plain bearer or cookies |
| **Scope erosion** (Spotify `product`) | any OAuth fact | **OAuth→cookie automatic fallback**; prefer facts that are *also* visible to an authed web call |
| **Cookie replay rejection** (UA/IP/rotation) | Duolingo, LeetCode, SO-public | test replay from a fresh TLS session per target; capture UA; else MPC (user IP) |
| **HTML/XPath fragility** (Reclaim's law) | none — every Tier-1 fact is **JSON** | **JSON-only launch set**; treat any HTML target as Tier-2+ maintenance liability |
| **Ownership gap** (public endpoints) | Codeforces, SO-public, LeetCode-public | bind handle→identity via notarized authed `/me` **or** a REP-nonce in the profile |
| **TLS 1.3-only targets** | unverified per target | verify prover suite support per target before launch; pin TLS 1.2 where the prover requires it |
| **Anti-goal: silent token exfiltration** | QR/remote-auth flows (excluded) | none of the 7 use QR remote-auth; credentials stay **on-device**, redacted, used once |

**Net:** the launch set is **7 proxy-mode, JSON-API, on-device-credential combos**, low-stakes-first, with GitHub as the hero and Duolingo as the consumer-virality second. The single constraint that would knock any of them out of "wow" is constraint #3 (bot/IP defense) — and we chose them precisely because none triggers it.
