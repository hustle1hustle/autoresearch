# REAL MODE — prove your real GitHub on your iPhone

The mock build is only for *feeling* the UX. A **real** proof needs three things
that can't be faked, and a **one-time setup (~half a day the first time)**. After
that, real proofs are instant. This is the plain checklist; each step links the
detailed guide.

> Who does what: **you** = GitHub App + (with your dev) deploy backend & notary;
> **Mac/dev** = build the prover xcframework + build to the iPhone. The app code
> is already written — going real is mostly setup + flipping 2 switches.

---

## Ingredient 1 — the prover engine (xcframework)  ⏱ ~1 h first time
The zkTLS engine that actually makes the proof. Built on a Mac from Rust.
- Follow **`../test-kit/setup/01-xcframework-build.md`** (run its `build-xcframework.sh`).
- Output → drop `TlsnProver.xcframework` into `../test-kit/tlsn-build/ios/`.
- In `project.yml`, **uncomment** the `dependencies: framework` block (bottom).
- `Sources/TLSN/UniFFIProver.swift` is already written and activates automatically.

## Ingredient 2 — a notary that allows `api.github.com`  ⏱ ~15 min
The public demo notary won't proxy GitHub (domain allow-list). Run your own.
- Follow **`../test-kit/setup/03-self-hosted-notary.md`** (Docker; allow-list incl. `api.github.com`).
- Deploy it somewhere with HTTPS (Fly.io / a small VPS + Caddy). You get a URL like `https://notary.yourdomain`.

## Ingredient 3 — real GitHub login  ⏱ ~20 min
- **GitHub App** (NOT a classic OAuth App — refresh tokens need a GitHub App): **`../test-kit/setup/02-oauth-apps.md` §A**. You get a **Client ID** (`Iv1.…`) + **Secret**.
- **Backend** that holds the secret (already written): **`../backend-stub/`** → put Client ID/Secret in `.env`, deploy (`fly deploy` per its README). You get a URL like `https://rep-oauth.fly.dev`. **Optional for the first DEBUG proof** — the scheme `GITHUB_CLIENT_SECRET` shortcut skips it (see *Flip the switches*).

---

## Flip the switches  ⏱ ~5 min  (Xcode scheme env vars — no code edit)
In Xcode: **Product ▸ Scheme ▸ Edit Scheme… ▸ Run ▸ Arguments ▸ Environment Variables**, add:

| Name | Value |
|---|---|
| `USE_MOCK_PROVER` | `false` |
| `USE_MOCK_AUTH` | `false` |
| `GITHUB_CLIENT_ID` | `Iv1.your_id` |
| `VERIFIER_URL` | your notary URL (e.g. the ngrok HTTPS URL) |
| `GITHUB_CLIENT_SECRET` | your secret — **DEBUG-only shortcut, see below** |
| `BACKEND_URL` | `https://rep-oauth.fly.dev` — *skip if using the DEBUG secret* |

**No backend needed for the FIRST proof:** in a **DEBUG** build, if `GITHUB_CLIENT_SECRET`
is set, the app exchanges the GitHub code **directly** — so you can skip Ingredient 3's
backend deploy for the very first test. (Release builds ignore the secret and require the
backend — secret never ships in a shipped app.)

Then build to your iPhone (cable, free Apple ID):
```bash
cd mobile-app/ios-host
xcodegen generate
open REP.xcodeproj          # pick your iPhone at the top, press ▶︎
```

## Auto-return (optional for the first real test)
The 1-tap auto-return back from GitHub (Hack 4) needs **AASA hosted on a domain you
own** (`../test-kit/setup/04-universal-links.md`). For your very first real proof you
can skip the polish — you'll just tap once to come back. Add AASA when you have `r3p.xyz`.

---

## What "done" looks like
Tap **Connect GitHub** → real Safari opens GitHub (your warm session) → authorize →
back in REP → **real `octocat · N contributions` notarized by your notary**. Re-open →
tap the card → **Face ID → real proof again in ~1 tap.**

## Honest scope
There's **no shortcut** around Ingredients 1–3 — any real on-device zkTLS proof needs a
prover engine + a notary that allows the target + a real login. The heavy one is the
xcframework build (Mac/Rust, scripted). Everything else is ~10–20 min each.
If a step fights you → `../test-kit/troubleshooting.md`.
