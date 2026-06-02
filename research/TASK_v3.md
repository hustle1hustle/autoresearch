# Research Task v3 — REP Onboarding Wow: the One-Tap Proof That Makes a User Flex

> v3 supersedes v2/v1. Unit of analysis = the **proof template (cohort × platform)**, not a persona. Wow is **emotional** (5-component rubric), measured in reactions — not clean JSON. **Tier/percentile beats raw count.** **Login friction is half the magic** (the spark was "log into Uber in one tap via Apple ID"). **Feasibility is a final gate only — reuse v1, don't redo it.** Original v1 deliverables archived in `research/v1/` as the feasibility lookup table.

## WOW rubric (score every template 1–5 on each; feasibility is NOT a component)
1. **Effortless** — ≤2 taps, no typing, perceived <~3s (login friction lives here).
2. **Recognition** — "it knows the real me".
3. **Tier/percentile payload** — resolves to a *named tier or elite slice* this cohort brags about. **Raw count ≈ 0.**
4. **Magic** — "I couldn't have faked that".
5. **Payoff (3-part)** — (a) flex badge + (b) gated-community/matched-offer unlock + (c) shareable story/achievement/leaderboard.
**Litmus:** would they screenshot & share it?

**Gold standard (deck):** "Spotify · Top 0.1% · 8yr", "Top 5% Traveler · 48 countries", "Strava · Gold · 11-day streak", "Amex Platinum · 8yr". **Anti-pattern:** "428 contribs" (raw, dev-only).

## Product (deck = ground truth)
REP = portable verifiable proofs (zkTLS) feeding a **User Context Graph** (on-device custody; "prove, don't show"). Model = **cohorts × platforms; users pick what to verify; templates built by AI, validated by community.** Base: **~3.5M crypto-native users, $0 CAC.** Wow surface = flex badges + gated communities (Frequent Travelers, Verified AI Devs, Music Power Users, Top Traders, High-Trust Merchants) + matched offers (−22% hotel, upgrades) + stories/leaderboards.

## Priority cohorts (GIVEN)
- **Crypto-native** — on-chain reads = separate trivial track (NOT zkTLS); zkTLS angle = CEX/off-chain (exchange tier, funded-account, PnL).
- **Music** — top %, minutes, top artist (Spotify Wrapped-style; mind the Spotify split).
- **Gaming** — rank/tier/hours/achievements (Steam, Riot, etc.).
- **Fitness** — tier/streak/distance (Strava, Whoop, Apple Health).
- **AI/dev** — GitHub stars/contributions (gate as a *tier*, never raw), AI spend.
- **Travel** — trips/yr, countries, loyalty tier.
- *(secondary: traders, merchants.)*

## Reuse from v1 (given — do NOT redo)
- Modes: proxy ~1–2s vs MPC ~3–15s; proxy verifier-IP fine on clean token-limited APIs, **flagged behind Cloudflare/Akamai** (→ MPC user-IP, or residential last-resort); **device-attestation targets = dead in any mode.**
- Default mode: proxy for clean APIs; MPC only behind a WAF; residential = last resort.
- **Spotify split:** `product` (tier) removed Feb-2026 → "I have Premium" via OAuth is DEAD. The *flex* (top %, minutes, top artist) lives on different endpoints — Stage 4 must separate dead-subscription from (likely-live) listening-stats.
- GitHub proxy-mode Rust skeleton — reuse its *format*.

## Stages & deliverables
- **Stage 1 → `10-templates.md`** — per cohort: platforms users are already logged into + candidate flex facts, as templates *(cohort, platform, tier fact, badge, community/offer, story)*. Mark crypto on-chain as a separate trivial track. No feasibility.
- **Stage 2 → `11-wow.md`** — score every template on the 5-rubric, **feasibility-blind**; rank within cohort + a cross-cohort top ~10. Penalize raw counts hard.
- **Stage 3 → `12-login.md`** — for the top templates, the source where the user is already logged in + the near-one-tap path (app-switch OAuth / cookie reuse / passkey). **Re-rank by `wow × login-effortlessness`.** Drop templates with no one-tap path.
- **Stage 4 → `13-feasibility.md`** — the engineering filter, LAST, using `research/v1/`: is the *tier fact* in stable JSON (and the *flex* endpoint, not a dead one)? bot/IP → proxy flagged? attestation → dead? ToS? Assign mode + build-risk. Kill the impossible, flag the fragile.
- **Stage 5 → `14-heroes.md`** — the genesis hero set: top templates maximizing `wow × low-friction` that pass the gate, spanning the crypto base + ≥2 universal cohorts. Spec each: cohort, flex badge, one-tap login, notarized request + claim schema + redaction, mode + why, graph node/edge → community + offer + story. Runnable skeleton.
- **Rewrite `SUMMARY.md`** — genesis set (each as a one-sentence flex), mode policy, on-chain-vs-zkTLS split, 30-day ship path.

## Anti-goals
Don't rank by feasibility; don't reward raw counts; don't collapse "meaningful" into "technically clean"; don't ignore login friction; don't spend zkTLS effort on on-chain facts; don't re-run v1 infra; no token-harvesting/remote-auth abuse; nothing whose core needs a ToS violation; no manual-password happy path; explicit consent + scoped tokens; client-side custody. Numbers, not adjectives.

## Open questions
1. Per cohort: the single tier/percentile fact that gets screenshotted (one sentence each).
2. Spotify split: is the listening-stats flex still API-reachable post-Feb-2026? Where exactly?
3. Which top flexes sit behind a true one-tap login vs code/password?
4. The genesis set: highest `wow × lowest-friction`, proxy-safe, spanning crypto base + ≥2 universal cohorts.
5. Per genesis template: which gated community + matched offer + story it unlocks.
