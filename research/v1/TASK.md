# Research Task — TLSNotary Proof UX: Find the Highest-Wow Login × Proof Combos

> This is the original task spec, preserved for reproducibility. Deliverables produced against it live alongside this file:
> `00-tlsnotary.md`, `01-auth-flows.md`, `02-targets.md`, `03-wow-combos.md`, `04-hero-flow.md`, `SUMMARY.md`.

## How to run this

You are an autonomous research agent. This is a multi-stage investigation, not a single-shot answer. Work stage by stage, write each deliverable to disk as you finish it, and **verify every claim against primary sources** — code you actually read, docs you fetch, flows you actually run — before you assert it. The hypotheses in this brief are my current best guess. Your job is to **confirm, correct, quantify, and extend** them. Where I'm wrong, say so and show the evidence.

**Operating principles (non-negotiable):**
1. **First principles.** Don't trust this brief. Re-derive the infra behavior from the TLSNotary source and live tests, not from blog posts (or from me).
2. **Numbers, not adjectives.** "Easy/fast/hard" must become taps, seconds, success-rate, KB, IP-flag-yes/no. Every difficulty claim is backed by a citation or a test you ran.
3. **Smallest case first.** Get one end-to-end flow real before generalizing. Make it work, then scale.
4. **Spec before code.** The output is a *decision + specs*, not a pile of half-built integrations.
5. **Show your work.** Cite URLs, link code paths / line numbers, paste observed flows and wall-clock timings.

## Mission

Find the set of **(platform × login flow × proof)** combinations that maximize **UX wow**: the user authenticates in the fewest taps/seconds, and we mint a *meaningful* verifiable proof on the other side. **Start with low-stakes / easy proofs** to nail the feel — fast, magical, zero friction — and map the path to higher-stakes proofs later. We're optimizing the wedge, not the endgame.

Single most important output: a **ranked shortlist of "launch flows,"** each specced end-to-end, plus **one hero flow** taken to an implementation spec.

## Product context — REP

REP is a **trust and coordination layer for humans, businesses, and AI agents.** It turns private web data into **portable, verifiable proofs (zkTLS)** that feed a **User Context Graph** — a compounding, user-owned graph of attested facts (subscriptions, usage, identity, reputation) that other apps and agents can consume *without the user re-proving from scratch*. Defensibility = the graph + the **Proof Graph Runtime** that composes proofs.

**Implication:** value of a proof = (how much it enriches the graph) × (how low the friction to mint it). Early on we deliberately favor **low friction over high stakes**. **Onboarding UX *is* the moat at seed stage.**

## Infra

**TLSNotary is primary** (open-source, EF/PSE). **Primus Labs is a secondary cross-reference only.** TLSNotary ships two modes:
- **MPC mode** (gold standard): prover+verifier jointly run the TLS handshake via MPC; no party holds full keys; request arrives from the user's IP; verifier doesn't learn the server online. Cost: heavy bandwidth → ~3–15 s. Browser MPC needs a WebSocket↔TCP proxy.
- **Proxy mode** (Apr 2026): the verifier connects to the server and forwards encrypted TLS; ZK proof verified after. ~1–2 s. Browser-clean. **Tradeoff: server sees the verifier's IP** → datacenter IP may be flagged; residential proxy weakens trust.

**This proxy-mode IP tradeoff is the crux.** Quantify when it bites and when it doesn't.

Other facts to confirm: notary JWT bearer auth; prover X.509 client certs; low-bandwidth setting for MPC; PSE's hosted proxy whitelists domains (self-host for arbitrary targets); Reclaim's 200+ providers, residential routing, "JSON stable / HTML fragile."

## The three binding constraints
1. **Auth friction** — authenticated session without typing a password? Taps + seconds, warm vs cold, iOS vs Android.
2. **Data extraction** — fact in a stable JSON XHR/API (durable) or only HTML (fragile)? Find the exact request.
3. **Bot / network defense** — Cloudflare/Akamai/PerimeterX? device attestation? Does proxy mode's verifier-IP get flagged → forcing MPC or a residential proxy?

**Key interaction:** "OAuth exists" ≠ easy. If the specific fact isn't in scope, you're forced onto the bot-defended web path.

## Stages & deliverables
- **Stage 0 → `00-tlsnotary.md`:** clone tlsn; read proxy + MPC paths; state each trust model from the code; run the demo against an authenticated target; wall-clock both modes; confirm/refute every "verified fact"; produce a mode-selection decision table.
- **Stage 1 → `01-auth-flows.md`:** auth-flow matrix (app-switch OAuth/PKCE, system-browser cookie reuse, passkeys/FIDO CDA, QR cross-device, device grant, magic-link/OTP): taps, seconds (warm/cold), iOS vs Android, token yielded, TLSNotary-proxy compatibility; recommended offer-ordering.
- **Stage 2 → `02-targets.md`:** target tiering; for each, the actual endpoint (JSON vs HTML); Ease score (1–5 per constraint) + Proof-Value score; Reclaim/Primus evidence; ToS posture; stability.
- **Stage 3 → `03-wow-combos.md`:** intersect 1×2 → top 5–8 (platform, login, proof) combos, ranked by (low friction × meaningfulness), low-stakes-first; per combo: flow with taps/seconds, mode + why, exact endpoint, claim, redaction, failure modes.
- **Stage 4 → `04-hero-flow.md`:** the single best low-stakes combo → implementation spec: auth handoff, notarized request, proof/claim schema, redaction, graph integration, runnable skeleton.
- **Top-level → `SUMMARY.md`:** the decision; default mode policy and what flips it; the residential-egress answer; the 30-day ship path.

## Anti-goals
No token-harvesting/abuse of remote-auth/QR endpoints; nothing whose core depends on violating ToS; no manual-password happy path; don't optimize for high-stakes first; don't park credentials server-side if client-side custody exists; no adjective-only claims.

## Open questions
1. Which Tier-2 targets flag proxy-mode verifier-IP → MPC/residential? Where's the line?
2. Single warm phone: app-switch OAuth vs system-browser cookie reuse — real numbers.
3. Best low-stakes hero (Spotify tier, GitHub contributions, Duolingo streak, Anthropic spend)?
4. JSON vs HTML per Tier-1 target, and historical stability?
5. How much does proxy mode simplify browser/mobile-web deployment vs MPC's WebSocket-proxy?
