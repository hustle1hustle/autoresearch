# Stage 3 — The Swiss-army-knife login router (centerpiece)

The thing REP's "connect account" calls. **Target-agnostic:** it takes a few cheap detection signals about the target + device, picks the **fastest blade that satisfies the Stage-0 contract** (yields a *target* bearer or cookie), and falls back gracefully. Blades = the Stage-1 methods; this is the runtime logic that chooses among them.

## Detection signals (cheap, gathered at connect time)
| Signal | How | Why it matters |
|---|---|---|
| `app_installed` | `canOpenURL:` (iOS) / package query (Android) | enables **app-switch OAuth** (biometric in the warm app) |
| `oauth_usable` | target offers OAuth/PKCE **and** the token is a **plain bearer** (not DPoP/mTLS-bound) | bearer = cleanest credential (redact one header) |
| `passkey_rp_is_target` | target advertises passkeys **and** the session we need is the target's own | passkey only helps if its RP **is** the target (Stage 0) |
| `target_is_apple_google` | the target itself is Google/Apple | the only case SiwA/Google yields a usable *target* credential |
| `platform` | iOS / Android | sets cookie-reuse friction (iOS consent tap) + autofill APIs |
| `warm` | **observed** by opening the system-browser surface (authed redirect = warm; login form = cold) | warm reuse is the floor; the probe *is* the happy path |

## The core insight that simplifies everything
**Always open the system-browser surface** — `ASWebAuthenticationSession` (iOS) / **Chrome Custom Tabs** (Android). It serves *both* the OAuth authorize flow *and* raw cookie-reuse, and **inherits the warm system-browser session in both**. The only branch is **which URL** you open and **which credential** you keep:
- OAuth usable → open the **authorize endpoint** → keep the **bearer**.
- else → open the **target's authenticated entry** → keep the **cookie jar**.
**Never** open login in an embedded `WKWebView`/`WebView` (isolated jar → re-login → OTP fallback; Stage 2). App-switch to the **native app** is just a faster variant when the app is installed (biometric in-app, then auto-return).

## Decision rules (first eligible wins; ordered by friction among contract-satisfying blades)
| # | Condition | Blade | Credential |
|---|---|---|---|
| R1 | `oauth_usable && app_installed` | **App-switch OAuth (PKCE)** → native app, biometric, auto-return | target **bearer** |
| R2 | `oauth_usable && !app_installed` | **System-browser OAuth** (open authorize URL in ASWebAuth/Custom Tab; warm-reuse auto-approves) | target **bearer** |
| R3 | `!oauth_usable` **and** `warm` | **System-browser cookie reuse** (Custom Tab silent / ASWebAuth + 1 consent) | target **cookie jar** |
| R4 | `!oauth_usable && !warm && passkey_rp_is_target` | **Passkey** (conditional UI / Credential Manager) → mints target session | target **cookie** |
| R5 | `target_is_apple_google` | **Sign in with Apple/Google** | target token |
| R6 | else (cold typed fallback, in the system-browser surface, autofill-assisted) | **SMS OTP → email OTP → password(last)** | target **cookie** |

## Pseudocode
```text
connectAccount(target, device):
  appInstalled = canOpen(target.appScheme)
  oauthUsable  = target.hasOAuth && !target.tokenBound      # plain bearer, replayable (Stage 0)

  # ── Tier-A: zero-typing, one-device, contract-satisfying ──
  if oauthUsable:
      if appInstalled:  return appSwitchOAuth(target).bearer        # R1  (return via custom-scheme/App-Link)
      else:             return systemBrowserOAuth(target).bearer    # R2  (warm reuse auto-approves)

  session = openSystemBrowser(target.authedEntry)   # ASWebAuth(iOS, 1 consent) | CustomTab(Android, silent)
  if session.authenticated:  return session.cookieJar               # R3  WARM cookie reuse
  if target.passkeys && target.isRP:  return passkey().cookieJar     # R4
  if target in {google, apple}:       return sso(target)             # R5

  # ── Tier-B: cold typed fallback, SAME system-browser surface, autofill on ──
  return smsOTP()      # Security Code AutoFill / SMS Retriever  (R6)
      ?? emailOTP()    # code, not magic link
      ?? password()    # LAST resort — anti-goal

  # invariants: never WKWebView/WebView;  always auto-return (custom scheme iOS / App Links Android);
  #             credential used once, client-side, redacted from the proof;  no server-side custody.
```

## The fallback ladder (when the one-tap path isn't there)
**warm cookie-reuse / app-switch OAuth  →  passkey (if RP=target)  →  SMS OTP (autofill)  →  email code  →  password (last).**
Each rung down adds friction (Stage 1 F-scores: ~4 → ~3 → ~16 → ~20 → ~30) but **none drops the user into an embedded WebView, a second device, or a magic link** (the three funnel-killers we explicitly avoid).

## iOS vs Android deltas (where the fastest path differs)
| | iOS | Android |
|---|---|---|
| Warm cookie-reuse surface | `ASWebAuthenticationSession` — **+1 consent tap** (unavoidable) | **Chrome Custom Tabs** — **silent, no prompt** (smoother) |
| Auto-return | **custom URL scheme** (Universal Link can strand the session) | **verified App Links** |
| Passkey/first-class | `ASAuthorizationController` + conditional UI (QuickType) | **Credential Manager** (one bottom sheet: passkey + SiwG + password) |
| OTP autofill | **Security Code AutoFill** (`oneTimeCode`, domain-bound) | **SMS Retriever** (silent) / **User Consent** (1 tap) |
| Net warm floor | **~2 taps** (consent + biometric/redirect) | **~1 tap** (silent reuse) |

The router is identical across platforms; only the surface (`ASWebAuthenticationSession` vs Custom Tabs), the return mechanism (custom scheme vs App Links), and the +1 iOS consent tap differ.
