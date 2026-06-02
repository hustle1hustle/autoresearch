# Stage 4 — Feasibility GATE (applied last; reuses `research/v1/`)

This is the engineering filter, applied **after** wow (Stage 2) and login (Stage 3) — never as a ranking axis. Lookups come from `research/v1/` (mode policy, proxy-IP line, attestation = dead). Per surviving template: **is the *flex* fact in stable JSON (the live endpoint, not a dead one)? → bot/IP: does proxy's datacenter-IP get flagged? → device attestation = dead? → ToS → assign mode + build-risk.**

**v1 mode policy (given):** proxy (~1–2 s) for clean token-limited JSON APIs; **MPC** (user's real IP, ~3–15 s) behind Cloudflare/Akamai WAFs; residential = last resort; **device-attested endpoints are dead in any mode**. A key v1/Stage-3 nuance confirmed by this stage's research: **bot walls (Cloudflare 403) hit server-to-server fetches, not the user's own browser TLS session that zkTLS notarizes** — so a WAF in front of a *public* API is a smaller blocker than a WAF doing *behavioral/IP* challenges.

## The gate table

| Template | Flex fact API-reachable? | Endpoint (JSON) | Bot/IP → proxy? | Attestation | ToS | **Mode** | **Build-risk** |
|---|---|---|---|---|---|---|---|
| **Spotify "#1 artist / top track"** | ✅ `/v1/me/top/*` survived Feb-2026 (`user-top-read`). ❌ "Top 0.1%" percentile = protobuf/cookie/seasonal → grey | `api.spotify.com/v1/me/top/{artists,tracks}` (JSON) | ✅ token-rate-limited, no behavioral WAF → **proxy OK** | No (web/API) | tightened Feb-2026; **5-user app cap** until Extended Quota | **Proxy** | **Med** — *not* the percentile; **app-quota wall** (mitigations below) |
| **GitHub "Top % stars / Verified AI Dev"** | ✅ stars in GraphQL (v1-proven); percentile derived offline | `api.github.com/graphql` (JSON) | ✅ proxy-safe (v1) | No | Clean | **Proxy** | **Low** (v1-proven) |
| **Lichess / Chess.com "title · rating"** | ✅ titles+ratings in public player JSON | `lichess.org/api/user/{u}`, `api.chess.com/pub/player/{u}` (JSON) | ✅ public API; user-session clean; low-volume proxy OK | No | Clean (public) | **Proxy** | **Low** — bind handle→user; percentile methodology-sensitive |
| **Farcaster "OG / Power Badge"** | ✅ public Neynar/Warpcast JSON; Pro/OG also on-chain | `api.neynar.com/...` (JSON) + SIWF | ✅ public, proxy-safe | No | OK | **Proxy / none** (SIWF+public) | **Low** — *often needs no zkTLS* |
| **Coinbase "tier / holdings"** | ⚠️ OAuth user/accounts ✅; "Coinbase One status" field **unconfirmed** | `api.coinbase.com/v2/user`,`/accounts` (JSON) | ✅ OAuth API, proxy-safe | No (OAuth API) | OK | **Proxy** | **Med** — tier endpoint unconfirmed; weak flex |
| **Whoop "Recovery / Strain"** | ⚠️ `recovery_score`/`strain` ✅; **"Whoop Age"/percentile NOT in API** | `api.prod.whoop.com/developer/v2/recovery` (JSON) | ✅ OAuth API, proxy-safe | No | OK | **Proxy** | **Med** — flex is a *daily metric*, soft badge |
| **Binance "VIP 0–9 / Verified PnL"** | ✅ VIP via `/sapi/v1/account/info` (key); PnL via `/bapi/.../leaderboard` (web cookie) | `api.binance.com/sapi/...`, `/bapi/...` (JSON) | ⚠️ `/sapi`+`/bapi` Cloudflare/WAF-fronted → **datacenter proxy-IP risky → MPC / in-browser** | **mobile app = YES (dead)**; **web = No** | Binance "no 3rd-party" → grey | **MPC / in-browser** | **High** — WAF, key-paste/pwd login, ToS-hostile |
| **Riot "Radiant / Challenger"** | ✅ LoL `league-v4` JSON; Valorant only via unofficial HenrikDev | `{plat}.api.riotgames.com/lol/league/v4` (JSON) | ⚠️ Cloudflare on auth; **API-key gating is the blocker** | No | **personal-key public use forbidden**; RSO approval | **Proxy** (if approved) | **High** — Riot prod+RSO approval (~3 wks) → fast-follow |
| **Strava "Local Legend / %"** | ❌ **iconic flexes not in API**; leaderboard dropped `athlete_id` (2024) → unverifiable | `api.strava.com/v3/athlete` (JSON, but not the flex) | ✅ API proxy-safe | No | **Hostile** (display-to-user-only; ban 3rd-party routing; paid sub Jun-2026) | Proxy | **High** — flex not mintable **+ ToS-hostile** → demote |
| **Airline / Hotel / Amex status** | ✅ but only in **HTML behind password+MFA** | loyalty portal **HTML** | ❌ Akamai + datacenter-IP flagged → **MPC/residential** | No (web) | password+MFA | **MPC/residential** | **High** — HTML-fragile, **not one-tap** → premium fast-follow |
| **Telegram "Top Spender / Premium"** | ❌ only via **MTProto** (`getStarsStatus`), not HTTPS | — (MTProto) | — | **protocol-dead** | web path = **anti-goal** | **DEAD** | **Kill** — needs Telegram Mini-App, not zkTLS |
| **Apple Health / Garmin** | ❌ no web API / partner-locked + TLS-fingerprinted | — | — | — | — | **DEAD** | **Kill** |
| **PSN** | ⚠️ unofficial only | NPSSO scrape | — | — | grey | — | **Kill** (login E) |

## Gate outcomes

**KILLED (infeasible for zkTLS):**
- **Telegram top-spender** — MTProto ≠ HTTPS web session; the only web path is the explicit token-exfiltration anti-goal. Great flex, wrong protocol. (Revisit only as a Telegram-native Mini App — not zkTLS.)
- **Apple Health** (on-device, no web API), **Garmin** (partner-locked + TLS-fingerprints clients), **PSN** (NPSSO cookie-scrape, login class E).

**DEMOTED to "premium / fast-follow" (high flex, but login or API or ToS breaks one-tap):**
- **Binance VIP/PnL** — *feasible on the web surface* and highest base-resonance, but WAF → MPC/in-browser, login is password+2FA/key-paste (not one-tap), ToS-hostile. Ship as the **premium crypto flex**, ~60 s, clearly not "one tap."
- **Airline/Hotel/Amex status** — feasible (Reclaim "Status Match" proves it across 100+ programs) but **password+MFA behind Akamai** → multi-step. Premium travel flex, not genesis.
- **Riot Radiant** — highest gaming flex but **API-approval-gated** (~3 wks) → fast-follow after the gate clears.
- **Strava** — keep only as a weak "recent activity" proof; the iconic flexes aren't API-mintable and ToS is hostile. Not a hero.

**PASSED clean (one-tap + proxy + low/med build-risk → genesis candidates):**
1. **GitHub "Top % stars / Verified AI Dev"** — Low risk, Proxy, clean ToS. *(v1-proven.)*
2. **Lichess / Chess.com "title · rating"** — Low risk, Proxy, clean public API. *(bind handle→user.)*
3. **Farcaster "OG / Power Badge"** — Low risk; SIWF + public API (zkTLS optional).
4. **Spotify "#1 artist / top track"** — Med risk (quota wall), Proxy. The universal wow magnet.
5. **Coinbase "tier"** / **Whoop "Recovery"** — Med risk, Proxy; weaker/softer flexes (bench for genesis+1).

### The Spotify quota wall — two concrete mitigations (it's a commercial friction, not an infeasibility)
1. **Extended Quota via REP's scale.** Spotify Extended Quota needs a registered business + 250k MAU; **REP already has ~3.5M users** — apply as the business and clear the cap. (Chicken-egg solved by the existing base.)
2. **Notarize the user's own session (the zkTLS-native path).** Reclaim's live Spotify provider rides the **user's authenticated session**, not your app's API quota — so the 5-user cap never binds. ToS-grey but quota-free, and it's exactly what zkTLS is for. Use OAuth where Extended Quota is granted; fall back to user-session notarization otherwise.

## What feeds Stage 5
Genesis = the PASSED set (Spotify, GitHub, Lichess, Farcaster) + **Binance as the demoted-but-included premium crypto flex** (because base-resonance demands it, with the friction stated honestly). This spans the **crypto base (Farcaster, Binance) + 3 universal cohorts (Music, AI-dev, Gaming)**.
