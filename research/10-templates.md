# Stage 1 — Template inventory (feasibility-blind)

**Unit = a template:** `(cohort, platform, the tier/percentile flex fact, the badge it yields, the gated community + matched offer it unlocks, the story artifact)`. No feasibility here (that's the Stage 4 gate). Flex facts are stated at their **aspirational best** (the screenshot a user *wants*); whether the exact percentile is API-reachable vs. Wrapped-grey is deferred to Stage 4. **Raw counts are deliberately excluded** unless they resolve to a tier/percentile (principle #3).

> **The "one-tap via Apple" north star:** for every template the question behind Stage 3 is "is the user already logged in on this device, and is entry an app-switch/cookie/passkey tap?" Templates are written platform-first *because* the platform is where the warm session already lives.

---

## Track 0 — Crypto on-chain (SEPARATE TRIVIAL TRACK — not zkTLS)
Wallet age, holdings tier, ENS, NFT/POAP holdings, DeFi positions, on-chain PnL → **public RPC/indexer reads, not zkTLS.** Ship as a trivial parallel track (sign a wallet message → read chain). **Do not spend zkTLS/TLSNotary effort here.** The crypto-native cohort's *zkTLS* value is the **off-chain/CEX** track below.

---

## Cohort: Crypto-native (off-chain / CEX) — *resonance with the 3.5M base*
| Platform | Flex fact (the screenshot) | Badge | Community | Matched offer | Story |
|---|---|---|---|---|---|
| **Binance** | "VIP 7" / "Top 1% 30-day volume" / "Verified +$1.2M futures PnL" | **Whale Trader** | Top Traders | fee rebates, alpha group | "Verified +$1.2M PnL · 2026" leaderboard |
| **Coinbase** | "Coinbase One · $250k+ tier" | Holder | Top Traders | premium support, events | net-worth tier card |
| **Prop firm (FTMO/etc.)** | "Funded $200k Trader · payout tier" | Funded Trader | Top Traders | scaling, capital | "Passed · $200k funded" |
| **Telegram** | "Top 1% Spender (Stars/gifts)" / "Premium · OG 2015" | Telegram Whale | base-native club | Stars perks | spender leaderboard |
| **Farcaster** | "Pro · Power Badge · OG 2023" | OG Caster | Verified crypto-social | channel access | account-age story |

## Cohort: Music — *the universal cultural flex (Wrapped ritual)*
| Platform | Flex fact | Badge | Community | Matched offer | Story |
|---|---|---|---|---|---|
| **Spotify** | "Top 0.1% of <artist> fans" / "#1 artist: <X>" / "Top 5% globally" | **Music Power User** | Music Power Users · per-artist fan clubs | presale/early ticket access, merch −X% | "Your 2026 sound: Top 0.1% of <artist>" |
| **Spotify** | "8-year listener · OG" (account age) | OG Listener | — | — | anniversary card |
| **Apple Music** | Replay top artist / minutes | Power Listener | Music Power Users | — | Replay-style card |
| **Last.fm** | "120k scrobbles · Top artist <X>" | Scrobbler | niche | — | scrobble milestone |

## Cohort: Gaming — *the highest in-cohort flex (rank is identity)*
| Platform | Flex fact | Badge | Community | Matched offer | Story |
|---|---|---|---|---|---|
| **Riot (Valorant)** | "Radiant · Top 0.03%" | **Elite Gamer** | per-game elite gate | tournaments, coaching, gear | rank leaderboard |
| **Riot (LoL)** | "Challenger" / "Master · Top 0.1%" | Elite Gamer | same | same | rank card |
| **Faceit (CS)** | "Level 10 · Top 1%" | CS Shark | CS club | scrims, gear | level card |
| **Chess.com / Lichess** | "2100 blitz · Top 2%" / title "FM/IM" | Chess Shark | chess club | tournaments | rating story |
| **Steam** | "Top 1% playtime in <game>" / rare-achiev % | Completionist | per-game | game discounts | achievement card |

## Cohort: Fitness — *universal, achievement-driven*
| Platform | Flex fact | Badge | Community | Matched offer | Story |
|---|---|---|---|---|---|
| **Strava** | "Top 5% runner · 2,400 km/yr" / "Local Legend" / "11-day streak" | **Endurance Gold** | runners/cyclists | gear −X%, race entry | streak/segment leaderboard |
| **Whoop** | "Top 10% Recovery" / "Whoop Age 25 (real 38)" | Recovery Elite | biohackers | device perks | age-gap story |
| **Peloton** | "Century Club · Top 5% output" | Power Output | Peloton club | class perks | output card |
| **Apple Fitness** | "365-day Move streak" | Streak Master | — | — | streak card |

## Cohort: AI / dev — *the deck's "Verified AI Devs" gate (tier, never raw)*
| Platform | Flex fact | Badge | Community | Matched offer | Story |
|---|---|---|---|---|---|
| **GitHub** | "Top 1% by stars" / "Verified AI Dev (maintainer of <AI repo>)" | **Verified AI Dev** | Verified AI Devs | API credits, early model access | repo/stars card |
| **Anthropic / OpenAI** | "Top 1% API spender · $X tier" | AI Power User | AI builders | credits, beta access | spend tier card |
| **Kaggle** | "Grandmaster · Top 100" | Kaggle GM | data club | compute credits | rank card |
| **Hugging Face** | "Top 1% downloads · model author" | Model Author | ML club | compute | downloads card |

## Cohort: Travel — *strongest status flex, but login is the question*
| Platform | Flex fact | Badge | Community | Matched offer | Story |
|---|---|---|---|---|---|
| **Airline (Delta/United/AA)** | "Delta Diamond Medallion" / "United 1K" | **Elite Flyer** | Frequent Travelers | −22% hotel, lounge, upgrades | "48 countries · Top 5%" |
| **Hotel (Marriott/Hilton)** | "Marriott Titanium · 8yr" / "Hilton Diamond" | Elite Guest | Frequent Travelers | suite upgrades | stay-night story |
| **Amex** | "Platinum · 8yr" *(deck cover item)* | Platinum | high-trust | partner offers | member-since card |
| **Booking.com** | "Genius Level 3" | Genius | travelers | discounts | trips card |

---

## Notes carried into later stages
- **Travel/Amex have the strongest *payload* (status is pure flex) but the weakest *Effortless*** — these brands are typically password-login, no OAuth (flagged for Stage 3 to confirm/kill).
- **Spotify, Riot, Strava, GitHub, Farcaster, Coinbase have real OAuth** → candidate one-tap logins (Stage 3 quantifies).
- **Chess.com / Lichess / Steam-public / Codeforces** expose facts with *no login* (public-by-handle) → cheapest entry but need **identity binding** (handle→user), already solved-pattern in v1.
- Every flex above is written as a **tier/percentile**; the Stage 2 rubric will zero out any that can only resolve to a raw count.
