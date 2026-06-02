# Stage 4 — Recommended default connect-account flow

The spec REP builds against. One CTA, the Stage-3 router underneath, the Stage-2 mechanics baked in. **Target metric: connect a *warm* account in ≤2 taps / ≤8 s / zero typing** (Android ~1 tap; iOS ~2 taps incl. the consent sheet). Cold: ≤6 taps / ≤40 s, typing only via autofill.

## The default flow
**Single CTA: "Connect <service>."** On tap, the router runs:
1. **Pre-signal:** app-installed? OAuth-usable (plain bearer)?
2. **Tier-A (zero-typing, one device):**
   - OAuth-usable **+ app installed** → **app-switch OAuth** (biometric in the warm app) → auto-return.
   - OAuth-usable **+ no app** → **system-browser OAuth** (authorize URL in `ASWebAuthenticationSession`/Custom Tab; warm session auto-approves).
   - **no usable OAuth** → **system-browser cookie reuse** (same surface, target's authed entry; warm = reused).
3. **Cold** (no app, no warm session): the target's own login renders **in that same system-browser surface** — assisted by passkey (Credential Manager / conditional UI) or **SMS OTP autofill**; the session then **persists, so the next connect is warm.**
4. **Auto-return:** custom URL scheme (iOS) / verified App Links (Android). **Never** an embedded `WKWebView`/`WebView`. Credential used once, client-side, redacted.

## Screen-by-screen

### iOS — warm, OAuth-usable, app installed *(the headline path)*
1. REP: tap **"Connect Spotify"** → app-switch to the Spotify app.
2. **Face ID** (returning user: consent auto-skipped) → auto-return to REP.
3. REP: **"Connected ✓"** → prover fires the notarized request with the bearer.

**≈ 2 taps (Continue + Face ID) · ~6–8 s · 0 typing.** ✅ meets target.

### Android — warm, cookie reuse, no app *(the smoothest path)*
1. tap **"Connect"** → **Chrome Custom Tab** opens the target's authed entry — **already logged in (silent, no prompt)** → auto-redirect back via App Link.
2. **"Connected ✓"**.

**≈ 1 tap · ~5 s · 0 typing.** ✅ best case.

### iOS — warm, cookie reuse, no app
1. tap **"Connect"** → `ASWebAuthenticationSession` → **consent sheet** "*REP wants to use spotify.com to Sign In*" → **Continue** → page already logged in → auto-return (custom scheme).
2. **"Connected ✓"**.

**≈ 2 taps · ~6–10 s · 0 typing.** ✅ meets target (the consent tap is the only iOS tax).

### Cold (any platform) — first-time login, then warm forever after
1. tap **"Connect"** → system-browser surface shows the target's **own login page** (NOT a WebView).
2. **Passkey** (Credential Manager / conditional UI, 1 tap + biometric) **or** **SMS OTP** (Security Code AutoFill / SMS Retriever, ~1 tap, no copy-paste).
3. auto-return → **"Connected ✓"**. The session **persists in the system browser → the next connect is warm (Tier-A).**

**≈ 3–6 taps · ~15–40 s · typing only via autofill.** Acceptable as the one-time cost; it upgrades the user to warm.

## Hard rules (baked into the spec)
- **System-browser surfaces only** (`ASWebAuthenticationSession` / Custom Tabs). **Never** embed login in `WKWebView`/`WebView` — that isolated cookie jar is what forces the email-code re-login (Stage 2 / the Spotify-beta cause).
- **Auto-return**: custom URL scheme (iOS), verified App Links (Android) — never strand.
- **Don't set `prefersEphemeralWebBrowserSession = true`** — it kills warm reuse.
- **No magic link, no QR, no embedded-WebView, no manual-password** in the happy path.
- **Credential custody on-device**, used once, redacted; nothing parked server-side.
- **Fallback ladder** (Stage 3): warm reuse / app-switch OAuth → passkey → SMS OTP → email code → password (last).

## Instrumentation (so "≤2 taps / ≤8 s" is measured, not asserted)
Log per connect: **taps, wall-seconds, warm-vs-cold, platform, blade chosen, drop-off step, and WebView-fallback incidence (target: 0).** Watch the **warm-rate** (share of connects that hit Tier-A) — raising it (by always using the system-browser surface) is the single biggest funnel win. A connect that fell to SMS/email OTP should be flagged as a *cold* event, and if it happened for a *warm* user it's almost certainly an accidental embedded-WebView regression (Stage 2) — alert on it.

## The one-paragraph recommendation
Ship **one "Connect" button** backed by the Stage-3 router: **app-switch OAuth when the app is installed and the token is a plain bearer; otherwise the system-browser surface** (`ASWebAuthenticationSession`/Custom Tabs) which transparently does OAuth-or-cookie-reuse and **inherits the warm Safari/Chrome session**; return via custom scheme / App Links; and only on a genuine cold start fall through the autofill-assisted OTP ladder — never into a WebView, QR, magic link, or typed password. That yields the **warm floor of ~1 tap on Android / ~2 taps on iOS, zero typing**, and turns every cold user warm for next time.
