# SUMMARY (v3) — REP onboarding: the one-tap proofs that make a user flex

*One page. Full work in `10-templates.md` → `11-wow.md` → `12-login.md` → `13-feasibility.md` → `14-heroes.md`. v1 infra (modes, the proxy-IP line) is the feasibility lookup in `research/v1/`.*

## The decision — a genesis set, not one hero
Ship a **wall of one-tap flex proofs**, ranked by **emotional wow × login-effortlessness**, gated by feasibility last. Genesis set (spans the crypto base + 3 universal cohorts):

| Flex (one sentence) | Cohort | Login | Mode | Role |
|---|---|---|---|---|
| *"Spotify · my #1 artist of 2026 is `<X>`"* | Music | 1-tap OAuth | Proxy | **viral hero** |
| *"Binance · verified +$1.2M PnL / VIP 7 — receipts, not LARP"* | Crypto | pwd+2FA (~1 min) | MPC/in-browser | **base co-hero (premium)** |
| *"Farcaster · OG since FID #1,234 · Power Badge"* | Crypto-social | SIWF 1-tap | Proxy/none | **ship-first anchor** |
| *"GitHub · Verified AI Dev · Top 1% by stars"* | AI/dev | 1-tap OAuth | Proxy | deck's AI-dev gate |
| *"Chess · FM · Top 2% blitz"* | Gaming | 1-tap OAuth/public | Proxy | universal gaming flex |

**Hero = Spotify "#1 artist"** (highest wow × true one-tap × universal — the Wrapped screenshot ritual). **Ship-first = Farcaster** (days; SIWF + public API de-risks the launch). **Base co-hero = Binance "Verified PnL"** (highest resonance for the 3.5M, premium friction stated honestly).

## Why these (the v3 thesis, proven)
Stage 2's top raw-wow list included **Binance (22)** and **Airline-status (21)** — both **collapsed at the login stage** (password + MFA, not one-tap), while **Spotify/GitHub/Farcaster/Lichess won on the warm app-switch OAuth "one-tap-via-Apple" feel.** **Login-effortlessness, not flex strength, separates the genesis set.** Then feasibility killed the impossible and demoted the high-friction.

## Default mode policy (reused from v1, unchanged)
**Proxy (~1–2 s, browser-clean) by default** for clean token-rate-limited JSON APIs — that's every genesis pick except Binance. **Flip to MPC** (user's real IP, ~3–15 s) only behind a Cloudflare/Akamai **behavioral** WAF — that's **Binance** (`/sapi`+`/bapi`). **Residential = last resort.** **Device-attestation endpoints are dead in any mode** → for CEX, notarize the **web** surface, never the attested mobile app. (Local v1 measurement: proxy 0.80 s vs MPC 1.30 s on loopback; real-world MPC ≫ that.)

## The on-chain vs zkTLS split (for the crypto base)
**On-chain facts (wallet age, holdings, ENS, NFTs, DeFi PnL) = a separate TRIVIAL track** — public RPC reads, sign-a-message, no zkTLS. **Do not spend zkTLS effort there.** The crypto base's *zkTLS* value is **off-chain/CEX**: Binance VIP/PnL (web session), Coinbase tier (OAuth), Farcaster (SIWF + public). **Telegram top-spender is zkTLS-dead** (MTProto ≠ HTTPS, and the web path is the token-exfiltration anti-goal) — revisit only as a Telegram Mini App.

## Seed questions — answered
1. **The screenshot fact per cohort:** Music → "my #1 artist"; Crypto → "verified +$X PnL / VIP 7"; Crypto-social → "OG · Power Badge"; AI-dev → "Verified AI Dev · Top 1% stars"; Gaming → "FM · Top 2%"; Fitness → "Recovery 99%" (soft); Travel → "Delta Diamond" (premium, not one-tap).
2. **Spotify split:** the *flex* lives — `GET /v1/me/top/{artists,tracks}` (`user-top-read`) **survived** Feb-2026 → "#1 artist/top track" is reachable JSON. The **"Top 0.1%" Wrapped percentile is grey-dead** (protobuf at `spclient.wg.spotify.com`, consumer cookie, seasonal). "Prove Premium" is permanently dead (`product` removed).
3. **One-tap vs password:** one-tap → Spotify, GitHub, Farcaster, Lichess, Coinbase, Whoop (warm app-switch OAuth / SIWF). Password+MFA (disqualified from one-tap) → **Binance, all airlines/hotels/Amex, PSN.**
4. **The genesis set:** the 5 above — highest `wow × low-friction`, proxy-safe (except Binance=MPC), spanning crypto base + Music/AI-dev/Gaming.
5. **3-part payoff:** Spotify→Music Power Users + artist presale + "2026 Sound" card; Binance→Top Traders + fee rebates + PnL leaderboard; Farcaster→token-gated channels + allowlist + OG story; GitHub→Verified AI Devs + API credits + repo-stars card; Lichess→chess club + tournament entry + rating card.

## 30-day path to ship the genesis set
1. **Week 1 — Farcaster** (SIWF + Neynar public read): ship the first badge + the graph write (`owns` + `og/power/score`). Proves the loop end-to-end with near-zero risk.
2. **Week 2 — Spotify hero** (proxy-mode prover vs `api.spotify.com/v1/me/top/artists`; redact bearer, reveal `items[].name`): the viral "#1 artist" card. Resolve quota via Extended-Quota application (REP's 3.5M) **or** user-session notarization.
3. **Week 3 — GitHub + Lichess** (both proxy, low-risk, mostly v1-proven): the AI-dev gate + the gaming flex; tier the GitHub stars (never raw counts).
4. **Week 4 — Binance premium** (MPC/in-browser web-session notarization of `/sapi/v1/account/info` VIP + `/bapi` PnL; Primus-style): the base co-hero, framed as "premium, ~1 min," never one-tap.
Each proof writes a node/edge into the User Context Graph → unlocks a gated community + matched offer + story, and compounds: the next consumer of "Top Trader" or "Verified AI Dev" pays zero proving cost. **Onboarding UX is the moat; the genesis wall builds it.**
