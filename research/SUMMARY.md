# SUMMARY — TLSNotary Proof UX: the launch decision

*One page. Full evidence in `00-tlsnotary.md` (infra, read from source + built locally), `01-auth-flows.md`, `02-targets.md`, `03-wow-combos.md`, `04-hero-flow.md`.*

## The decision
**Launch a "wall of instant proofs" built on TLSNotary _proxy mode_ against clean JSON APIs, hero = "Prove your GitHub contributions."** The wedge is seven low-stakes, JSON-only, on-device-credential combos, low-friction first:

1. **GitHub** — contributions (OAuth `read:user`, proxy) — **HERO**
2. **Duolingo** — streak/XP (system-browser cookie, proxy) — consumer virality
3. **Strava** — activities (OAuth, proxy)
4. **LeetCode** — solved/rating (cookie, proxy)
5. **Codeforces** — rating (public + identity-bind, proxy)
6. **Stack Overflow** — reputation (OAuth `/me`, proxy)
7. **Anthropic Console** — spend (Admin key, proxy) — niche B2B/agent credibility badge

Every one exposes its fact on a **token-rate-limited JSON API**, so proxy mode's datacenter verifier-IP is *not* flagged → ~1–2 s proofs, browser-clean. That combination — clean API + proxy mode — *is* the wow.

## Default mode policy (and what flips it)
**Default = Proxy** (fast ~1–2 s, browser-clean: the verifier terminates the WebSocket *and* does the TCP, so nothing extra to host). Verified from source: `proxy.rs:215` (verifier opens the socket) and the browser-deployment clarification in `00-tlsnotary.md`. My local build: **proxy 0.80 s vs MPC 1.30 s** on loopback (a floor — real-world MPC is far worse; see below).

**Flip to MPC when constraint #3 (bot/network defense) turns hostile** — i.e., the *data endpoint* sits behind Cloudflare/Akamai/Imperva/DataDome with IP-reputation or TLS-fingerprint blocking (Amazon, Uber, Ticketmaster, X, Instagram, Spotify's internal endpoints). MPC sends the request from the **user's real residential/mobile IP** and needs no network-trust assumption — at the cost of a **~13 s preprocessing floor** (30 MB garbled-circuit upload; **12.5× slower than proxy at 5 Mbps**, shrinking to 1.8× at 1 Gbps). **Decline entirely** when the endpoint requires **device attestation** (Play Integrity/App Attest — Revolut retail, hardened bank/social apps): neither proxy nor MPC can forge it.

> Decision rule: *clean dev/public API → Proxy. WAF'd consumer surface → MPC (accept the latency). Device-attested endpoint → don't build it.*

## The residential-egress question, answered
**Don't route proxy mode through a residential proxy as the default.** It restores a user-like IP but (a) inserts a third party into the network path who could in principle interpose — **weakening proxy mode's single security assumption** (verifier↔server integrity) — and (b) re-introduces the vendor dependency we're avoiding. Honest hierarchy for a flagged target: **MPC (user-IP, no extra trust) > proxy-via-residential (fast, weaker trust) > datacenter-proxy (will be blocked).** Reclaim leans on residential routing precisely because their model exposes the same IP; we keep it as a last resort, not a default, and never for the Tier-1 wedge (which doesn't need it).

## Seed questions — direct answers
1. **Where does proxy-IP get flagged (→MPC/residential)?** On consumer-app surfaces behind behavioral WAFs (Amazon, Uber, Ticketmaster, X, IG/TikTok, post-lockdown Spotify internals). **Not** on developer/public APIs (GitHub, Strava, Codeforces, StackExchange, Duolingo's versioned API, Anthropic, Wise) — they rate-limit by token, not IP. **The line is the data endpoint's bot posture, not the brand.** Harder line: device attestation defeats *both* modes.
2. **Single-phone warm user: app-switch OAuth vs cookie reuse?** **OAuth wins for a warm/returning user when the fact is in a plain-bearer scope** (1–2 taps; consent auto-skipped on repeat; redact one header). Cookie reuse is forced when the fact is web-only/scope-less and costs an unavoidable consent sheet on iOS (Android CCT is silent, closing the gap). The real decider is the **scope gate**, not the mechanism.
3. **Best low-stakes hero (wow-per-effort)?** **GitHub contributions** > Duolingo streak > Strava > Anthropic spend. GitHub: cleanest (in-scope plain bearer, stable-since-2016 JSON, clean ToS, proxy-safe, Reclaim-proven, audience = our seed users). Duolingo has higher virality but cookie-path friction + grey ToS. Anthropic is high-value but admin-key-gated and niche.
4. **JSON vs HTML, and stability?** All Tier-1 facts are **JSON** and historically stable: GitHub GraphQL (2016+), Strava v3, StackExchange 2.x (2013+), Codeforces REST, Duolingo `/2017-06-30/` (6+ yrs), Anthropic Admin API. Reclaim's law confirmed: **JSON-API providers stay stable; HTML/XPath break on redesigns** → JSON-only launch set. (Spotify is the cautionary tale — it *removed* the `product` tier field from its API in Feb 2026, independently verified; tier-proof is dead, listening-history survives.)
5. **Does proxy mode simplify browser/mobile-web deployment?** **Yes, decisively.** Browser MPC needs a separately-hosted **WebSocket↔TCP proxy** (browsers can't open raw TCP). In proxy mode the browser prover speaks WebSocket to the verifier and **the verifier does the TCP** — so there's **nothing extra to ship or host**. This is a core reason proxy mode is the default.

## 30-day path to ship the hero (detail in `04-hero-flow.md`)
1. GitHub OAuth app (`read:user`), PKCE + app-switch, token stays on device.
2. TLSNotary **verifier/notary** accepting **proxy** sessions over WebSocket, allow-listing `api.github.com`, with an attestation signing key.
3. **Prover** (app/WASM): `POST api.github.com/graphql { viewer{ login contributionsCollection… } }`; **redact** `Authorization`, **reveal** `login`+`totalContributions`+the query.
4. Emit the **Verifiable Context Claim** → write the `owns` edge + `contributions.2026` attribute into the **User Context Graph** (90-day expiry).
5. Wire the (unneeded-but-safe) **OAuth→cookie** and **proxy→MPC** fallbacks; verify GitHub's TLS suite is prover-supported.
6. Demo a shareable, attestation-backed badge; measure real warm/cold taps+seconds; then add **Duolingo** and **Strava**.

**Bottom line:** proxy mode + clean JSON APIs is the seed-stage moat-builder — instant, delightful, nothing to host. Ship GitHub first; every subsequent proof a user mints (Duolingo, Strava, SO…) attaches to the same graph subject, so the *next* consumer of "active developer" pays zero proving cost. That reuse is the defensibility.
