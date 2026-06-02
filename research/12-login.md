# Stage 3 — How they log in (near-one-tap), and the re-rank

The spark was "log into Uber in one tap via Apple ID." Here we find, for each top template, **the source where the user is already warm** and **the login class**, then **re-rank by `wow × login-effortlessness`**. Login data uses the v1 auth matrix (`research/v1/01-auth-flows.md`) + this stage's platform research.

## Login classes (effortlessness)
- **A — True one-tap:** warm **app-switch OAuth**, plain bearer, no typing (≤2 taps, ~3–8 s). *The Apple-ID feel.*
- **B — Public, no login:** fact readable by handle → ~1 tap, **but needs identity-binding** (OAuth `/me` in the same notarized session, or a REP-nonce in the profile).
- **C — OAuth but clunky:** app-switch exists but breaks (deep-link bugs, redirect friction) → 3–5 taps.
- **D — Password (+ MFA):** typed password and often an email/SMS code → **fails the one-tap promise** (5–9 taps). *zkTLS-feasible ≠ one-tap.*
- **E — QR cross-device / fragile:** second screen or cookie-scrape → friction + anti-goal hazard.

## Per-template login (top templates)

| Template (flex) | Warm source | Login class | Taps / sec (warm) | Credential | Notes |
|---|---|:--:|---|---|---|
| **Spotify "#1 artist / top track"** | Spotify app (warm) | **A** | 2 / ~3–5 s | plain **bearer** (`user-top-read`, 1h) | SDK app-switches to the installed client; no password typed. v1-class clean. |
| **GitHub "Top % stars / Verified AI Dev"** | GitHub app / github.com session | **A** | 2–3 / ~7–10 s | plain bearer (`read:user`) | v1-proven, proxy-safe. |
| **Lichess "GM/IM/FM · rating"** | lichess.org | **A/B** | 1–2 / ~3–6 s | OAuth2 **PKCE, no secret, ~1-yr token** (or public read) | Best-in-class binding; public read also works. |
| **Chess.com "title · Top 2%"** | chess.com | **B** (OAuth for bind) | 1 / ~3 s + bind | public JSON; OAuth/PKCE to bind | UA header required; bind handle→user. |
| **Whoop "Recovery 99% / Strain"** | Whoop app | **A** | 2 / ~4–6 s | OAuth2 bearer (`read:recovery`) | `id.whoop.com` app-switch. Flex is a *daily metric* (weaker badge). |
| **Farcaster "OG / Power Badge"** | Warpcast app | **A** (mobile) / E (desktop QR) | 1–2 / ~4 s | Sign-in-with-Farcaster | One-tap on mobile; QR on desktop. Crypto-native warm. |
| **Coinbase "tier / holdings"** | Coinbase app | **A** | 2 / ~5–8 s | OAuth2 bearer | *(Stage-4 confirms which tier facts are in scope.)* |
| **Strava "Top 5% / Local Legend"** | Strava app | **C** | 3–5 / ~10–15 s | OAuth bearer | Documented deep-link/email-input breakage; **and the iconic flexes aren't in the API** (Stage 4). |
| **Riot "Radiant / Challenger"** | Riot session | **C** | 3–4 / ~10–15 s | RSO OAuth | **API-gated** (24h dev keys, RSO approval) → fast-follow, not genesis. |
| **Binance "VIP / Verified PnL"** | Binance app | **D** | 6–9 / ~30–60 s | password + 2FA | No broad 3rd-party OAuth; heavy WAF. *(Stage 4: likely attestation/WAF-gated.)* |
| **Airline "Diamond" / Hotel "Titanium"** | loyalty portal | **D** | 6–9 / ~30–90 s | password + **mandatory email/SMS MFA** | Akamai; **no passkey/OAuth on any US major**; datacenter-IP flagged. **Not one-tap.** |
| **Amex "Platinum · 8yr"** | amex.com | **D** | 6–9 / ~30–90 s | password + MFA | Same as airlines. |
| **PSN "Trophy level"** | — | **E** | many | NPSSO cookie scrape | Worst login in the set; drop. |

## Re-ranked by `wow × login-effortlessness`

**Tier 1 — one-tap AND high flex (genesis candidates):**
1. **Spotify "#1 artist / top track"** — wow high × **A**. The cultural one-tap hero. *(Flex is the named top item, not the grey percentile.)*
2. **GitHub "Top % stars / Verified AI Dev"** — strong × **A**. Cleanest end-to-end; the deck's AI-dev gate.
3. **Lichess / Chess.com "title · rating"** — solid × **A/B**. Lowest-friction; titles are universally legible.
4. **Farcaster "OG / Power Badge"** — medium × **A**. The clean **crypto-base** one-tap (pending Stage-4 endpoint check).
5. **Coinbase "tier"** — medium × **A**. Crypto-base, real OAuth (pending Stage-4 scope check).
6. **Whoop "Recovery Elite"** — good × **A**, but the flex is a daily metric → softer badge.

**Tier 2 — high flex but login (or API) crushes one-tap → premium fast-follow, NOT genesis:**
- **Binance VIP/PnL** (D + WAF), **Airline/Hotel/Amex status** (D + Akamai), **Riot Radiant** (C + API-gated). Each is a *great flex behind a multi-step login or a gated API* — ship later with a "premium, ~60 s" framing, never promised as one-tap.

**Dropped:** PSN (E), Apple Health/Garmin (no usable API — Stage 4), Strava as a *hero* (login C **and** the iconic flexes aren't API-mintable + ToS-hostile — keep only as a low-confidence "recent-activity" proof).

## The decisive interaction (why this re-rank matters)
Stage 2's top-5 by raw wow included **Binance (22), Airline (21)** — both **collapse here** because their login is password+MFA (D). Meanwhile **Spotify (held), GitHub (held), Lichess (rose)** win precisely because the warm session + app-switch OAuth delivers the "one tap via Apple" feel. **Login effortlessness, not flex strength, is what separates the genesis set** — exactly the v3 thesis. Stage 4 now gates the survivors on engineering feasibility.
