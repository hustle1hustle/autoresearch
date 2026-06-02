# Stage 5 — Genesis hero set

The templates that maximize **wow × low-login-friction** and pass the Stage-4 gate, chosen to span the **crypto-native base (Farcaster, Binance)** + **three universal cohorts (Music, AI-dev, Gaming)**. Each is specced: flex badge → one-tap login → notarized request + claim schema + redaction → mode + why → graph node/edge → the 3-part payoff (community + offer + story).

**Ship order:** **Farcaster first** (days — SIWF + public API, de-risks the launch, base-native), **Spotify as the viral hero** (the screenshot magnet), then **GitHub + Lichess** (clean, fast), with **Binance** as the premium base flex. Hero = **Spotify "#1 artist of 2026"** (highest wow × true one-tap × universal); base co-hero = **Binance "Verified PnL"** (highest resonance for the 3.5M).

---

## ★ HERO — Music · Spotify "Your #1 artist of 2026"
- **Flex badge:** *"Spotify · #1 fan of <Artist> · Top track <Song> · 2026"* (named-top-item; the Wrapped screenshot ritual). *(NOT "Top 0.1%" — that percentile is protobuf/cookie/seasonal, grey-dead; Stage 4.)*
- **One-tap login:** app-switch OAuth → the warm Spotify app (2 taps, ~3–5 s), scope `user-top-read`, plain **bearer** (1 h). No password typed.
- **Notarized request:** `GET https://api.spotify.com/v1/me/top/artists?time_range=long_term&limit=5` (+ `/tracks` for the song). JSON: `{"items":[{"name":"<Artist>", "genres":[…]}, …]}`.
- **Claim:** *"As of `<date>`, `api.spotify.com` reported this user's top artist (long-term) = `<Artist>` (top-5: …)."* Ownership intrinsic — `/v1/me/*` is the token holder's own data.
- **Redact:** `Authorization: Bearer …`. **Reveal:** the request path + `items[].name`.
- **Mode = Proxy** — `api.spotify.com` is token-rate-limited, no behavioral WAF → datacenter verifier-IP fine (~1–2 s, browser-clean). **Quota caveat (Stage 4):** official OAuth has a 5-user cap until Extended Quota → either apply via REP's 3.5M-user scale, or notarize the user's own session (Reclaim-style, quota-free, ToS-grey).
- **Graph:** `(user)-[owns]→(account:spotify/<id>)-[attr]→ top_artist.2026 = <Artist>`. **Payoff:** badge → **Music Power Users** + per-artist fan clubs → **artist presale / early-ticket access, merch −X%** → a shareable "Your 2026 Sound" story card. *This is the wow that drives organic sharing.*

### Runnable skeleton (proxy mode; reuses the v1 GitHub format in `research/v1/04-hero-flow.md`)
```rust
// Only the deltas from the v1 GitHub proxy skeleton are shown; the Session/driver,
// VerifierCommitStart::Proxy scaffold, prove()/verify() halves are identical.
const HOST: &str = "api.spotify.com";
const PATH: &str = "/v1/me/top/artists?time_range=long_term&limit=5";

// PROVER (REP app / WASM): proxy mode — verifier opens the TCP to api.spotify.com.
let prover = handle
    .new_prover(ProverConfig::builder().build()?)?
    .commit(ProxyTlsConfig::builder().server_name(DnsName::try_from(HOST)?).build()?)
    .await?;
let (tls, prover) = prover.connect(
    TlsClientConfig::builder()
        .server_name(ServerName::Dns(HOST.try_into()?))
        .root_store(mozilla_roots())          // real WebPKI roots
        .build()?,
)?;
let (mut sender, conn) = hyper::client::conn::http1::handshake(TokioIo::new(tls.compat())).await?;
tokio::spawn(conn);
let auth = format!("Bearer {access_token}");
let req = Request::builder()
    .method("GET").uri(format!("https://{HOST}{PATH}"))
    .header("Host", HOST).header("Authorization", &auth)
    .header("Accept","application/json").header("Connection","close")
    .body(Empty::<Bytes>::new())?;
let resp = sender.send_request(req).await?;            // 200 + JSON {items:[{name,…}]}

// SELECTIVE DISCLOSURE: reveal request path + items[].name; REDACT the bearer.
let mut b = ProveConfig::builder(prover.transcript());
b.server_identity();                                   // reveal api.spotify.com
let sent = prover.transcript().sent();
let pos = sent.windows(auth.len()).position(|w| w==auth.as_bytes()).unwrap();
b.reveal_sent(&(0..pos))?;                             // before token
b.reveal_sent(&(pos+auth.len()..sent.len()))?;         // after token (path/query)
b.reveal_recv(&(0..prover.transcript().received().len()))?;   // reveal artist names
prover.prove(&b.build()?).await?;
// VERIFIER (proxy): TcpStream::connect((HOST,443)); assert server==api.spotify.com;
// parse items[0].name -> top_artist -> sign VCC.
```

---

## ★ BASE CO-HERO — Crypto · Binance "Verified +$X PnL / VIP 7"
- **Flex badge:** *"Binance · VIP 7"* and/or *"Verified +$1.2M futures PnL · 2026"* — "receipts, not LARP," the ultimate flex in a base drowning in unverifiable PnL screenshots.
- **Login:** ⚠️ **not one-tap** — Binance OAuth is partner-gated; realistic path = password + 2FA web login (zkTLS notarizes the **web session**), or paste a read-only API key. ~30–60 s. Ship with an honest "premium, ~1 min" framing.
- **Notarized request:** VIP → `GET https://api.binance.com/sapi/v1/account/info` (HMAC key) → `{"vipLevel":7,…}`; PnL → `/bapi/futures/v2/private/future/leaderboard/getOtherPosition` (web cookie) → `{pnl, roi, rank}`.
- **Claim:** *"Binance reported VIP level 7 / verified futures PnL +$X."* **Redact:** API-key signature / session cookie. **Reveal:** `vipLevel` / `pnl`.
- **Mode = MPC (or in-browser)** — `/sapi`+`/bapi` are Cloudflare/WAF-fronted → a datacenter proxy-IP risks blocks → use the **user's real IP (MPC)**. **Never the mobile app** (device attestation = dead). ToS-grey (Binance disallows 3rd-party) → user-initiated, own-data only.
- **Graph:** `(user)-[owns]→(account:binance/<id>)-[attr]→ vip=7 / pnl_2026=+$X`. **Payoff:** **Top Traders** gate → **fee rebates / alpha groups / copy-trade lead** → verified-PnL **leaderboard**. *(Primus already notarizes the Binance TLS surface — proven-doable.)*

---

## Crypto-base anchor — Farcaster "OG · Power Badge" *(ship first; days)*
- **Flex badge:** *"Farcaster · OG since FID #1,234 · Power Badge · Pro"* + Neynar quality score → *"Top 5% caster."*
- **One-tap login:** **Sign In With Farcaster (SIWF/AuthKit)** — the "Sign in with Google" of crypto, native to the base. ~1–2 taps.
- **Request:** `GET https://api.neynar.com/v2/farcaster/user/bulk?fids={fid}` → `power_badge`, `experimental.neynar_user_score`, `fid`, `follower_count`.
- **Claim:** *"FID 1234 (OG, FID<10k), power_badge=true, score=0.9."* **Mode = Proxy / none** — mostly **SIWF + public API** (zkTLS optional; only Warpcast-private fields need it). **Build-risk: Low** — fastest genesis ship.
- **Graph:** `(user)-[owns,SIWF]→(account:farcaster/1234)-[attr]→ og=true,power=true,score=0.9`. **Payoff:** badge → token-gated **channels/allowlists** → channel access → "OG since 2023" story. *Honest note: this showcases the graph more than zkTLS; it's the frictionless warm-up that earns the first habit.*

---

## AI-dev gate — GitHub "Top 1% by stars · Verified AI Dev"
- **Flex badge:** *"Verified AI Dev · Top 1% by stars · maintainer of <repo> (Yk⭐)"* — tiered, **never the raw "428 contribs"** anti-pattern.
- **One-tap login:** GitHub OAuth app-switch (`read:user`/`public_repo`), plain bearer (v1-proven). 2–3 taps.
- **Request:** `POST https://api.github.com/graphql` → `viewer{ login repositories(ownerAffiliations:OWNER,first:100){ nodes{ stargazerCount nameWithOwner } } }`; sum stars; percentile computed offline against the public stars distribution. "Verified AI Dev" = OWNER/contributor of a repo on a curated AI-repo allowlist.
- **Claim:** *"github:octocat, Σ owned-repo stars = 12,400 (Top 1%); maintains <AI repo>."* **Redact:** `Authorization`. **Mode = Proxy** (v1-proven, clean ToS). **Build-risk: Low.**
- **Graph:** `(user)-[owns]→(account:github/octocat)-[attr]→ stars=12,400, ai_dev=true`. **Payoff:** **Verified AI Devs** gate (the deck's named community) → **API credits / early model access** → repo-stars story.

---

## Gaming — Lichess / Chess.com "FM · Top 2%"
- **Flex badge:** *"Chess · FM · 2300 blitz · Top 2%"* — FIDE-grade titles are universally legible.
- **Login:** **Lichess OAuth2 PKCE** (no client secret, ~1-yr token) for ownership-binding, or public read by handle. 1–2 taps.
- **Request:** `GET https://lichess.org/api/user/{u}` → `{title:"FM", perfs:{blitz:{rating:2300}}}` (Chess.com twin: `api.chess.com/pub/player/{u}` + `/stats`). Bind handle→user via `GET /api/account` in the same notarized session.
- **Claim:** *"lichess:<user>, title FM, blitz 2300 (Top ~2%)."* **Redact:** auth header (binding call). **Mode = Proxy** — public JSON; the user's own TLS session clears Cloudflare. **Build-risk: Low** (percentile is methodology-sensitive — state the basis).
- **Graph:** `(user)-[owns]→(account:lichess/<u>)-[attr]→ title=FM, blitz=2300`. **Payoff:** **chess club** / rated arenas → tournament entry / coaching offers → rating story. *(Riot "Radiant" is the higher flex but API-approval-gated → fast-follow once Riot prod+RSO clears.)*

---

## Genesis set at a glance

| Template | Cohort | Mode | Login | Build-risk | Role |
|---|---|---|---|---|---|
| **Spotify "#1 artist"** | Music | Proxy | 1-tap OAuth | Med (quota) | **viral hero** |
| **Binance "Verified PnL / VIP"** | Crypto | MPC/in-browser | pwd+2FA (~1 min) | High | **base co-hero (premium)** |
| **Farcaster "OG / Power"** | Crypto-social | Proxy/none | SIWF 1-tap | Low | **ship-first anchor** |
| **GitHub "Top 1% stars / AI Dev"** | AI/dev | Proxy | 1-tap OAuth | Low | the deck's AI-dev gate |
| **Lichess "FM · Top 2%"** | Gaming | Proxy | 1-tap OAuth/public | Low | universal gaming flex |

**Bench (genesis+1):** Coinbase tier, Whoop recovery (clean but softer flex), Riot Radiant (after API approval), Airline status (premium, password). **Killed:** Telegram (MTProto+anti-goal), Apple Health/Garmin/PSN.
