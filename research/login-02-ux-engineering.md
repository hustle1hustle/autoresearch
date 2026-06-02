# Stage 2 — "Don't kill the UX" engineering playbook

The concrete mechanics that drive connect-account drop-off to the floor. Sourced from the platform docs (Apple / Chrome / Android / IETF) gathered for this stage.

## 1. Warm-state detection & cookie reuse — the biggest lever
**Use the system browser, inherit its session.** A session the user already has at service X in Safari/Chrome can be reused with near-zero friction — *if* you open the right surface:

| Platform | Surface | Shares system-browser session? | Warm friction |
|---|---|---|---|
| **Android** | **Chrome Custom Tabs** | **YES — shared cookie jar, NO prompt** ([Chrome docs](https://developer.chrome.com/docs/android/custom-tabs); [Chromium FAQ](https://chromium.googlesource.com/chromium/src/+/refs/tags/125.0.6422.16/docs/security/custom-tabs-faq.md)) | **~0–1 tap, silent** |
| **iOS** | **`ASWebAuthenticationSession`** | **YES — Safari-cookie-backed**, but **one mandatory consent tap** ([Apple](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)) | **~1 tap (consent) + auto-redirect** |

**Detecting warm vs cold:** you can't read the system browser's cookies (sandboxed), so **detect by attempting**: open the system-browser surface to the target's authenticated entry/authorize URL — a **warm** user is redirected straight back to the callback (session present); a **cold** user is shown the target's login form *in that same surface* (and whatever they do there persists for next time). So the "probe" *is* the happy path — no separate detection step. Pre-signals that pick the blade before opening: **app-installed check** (`canOpenURL:` / Android package query) → app-switch OAuth; **passkey availability** (conditional-`mediation` probe) → passkey.

**Caveats (cite, don't hand-wave):** iOS consent prompt is **unavoidable** in shared mode; **`prefersEphemeralWebBrowserSession = true` kills warm reuse** (no cookie sharing — never set it if you want SSO) ([Apple](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/prefersephemeralwebbrowsersession)); **ITP / cookie-partitioning** can break flows that lean on third-party cookies even with a first-party session; warm reuse only helps if the live session is in the **system** browser (Safari/Chrome), not another browser and **not REP's embedded WebView** (§2).

## 2. The `WKWebView` trap — never log in inside an embedded WebView
**An app-embedded `WKWebView` (iOS) / `WebView` (Android) has its own isolated cookie store, separate from Safari/Chrome.** A fresh WebView therefore **does not see the user's system-browser login** → the service sees an unrecognized client → it **falls back to a fresh credential challenge, commonly an email/SMS one-time code** ("we don't recognize this login"). iOS: `WKWebView` uses its own `WKWebsiteDataStore`, and being out-of-process, even app-held `HTTPCookieStorage` cookies aren't auto-shared in ([Apple — WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore); [forums 95301](https://developer.apple.com/forums/thread/95301)). Android `WebView`'s `CookieManager` is likewise isolated from Chrome.

> **Open-question #2 answered (the Spotify email-code in the beta):** the symptom — a service bouncing the user to an **email code** instead of recognizing an existing session — is the **signature of login happening inside an embedded `WKWebView`** (isolated jar → re-login). **The fix that flips it to one-tap:** run the login in **`ASWebAuthenticationSession` (iOS) / Custom Tabs (Android)**, which are **system-browser-cookie-backed** and *would* see the existing Spotify session and skip the code. (Also note `SFSafariViewController` is **not** a substitute — iOS 11 isolated its data store; Apple explicitly says use `ASWebAuthenticationSession` to share with Safari. [Apple](https://developer.apple.com/documentation/safariservices/sfsafariviewcontroller))

## 3. Auto-return deep links — never strand the user
Per [RFC 8252](https://www.rfc-editor.org/rfc/rfc8252.html) native auth must return to the app. The reliable returns:
- **iOS:** use a **custom URL scheme** for the `ASWebAuthenticationSession` callback — it fires the session's `completionHandler` directly. **Avoid a Universal-Link callback for this**: a Universal Link can fire `scene(_:continue:)` instead and **leave the auth sheet undismissed/the app stranded** ([Apple forums 671458](https://developer.apple.com/forums/thread/671458)).
- **Android:** use **verified App Links** (`android:autoVerify`, `assetlinks.json`) so the redirect **opens REP directly with no chooser** ([Android](https://developer.android.com/training/app-links/verify-applinks)).

## 4. Single-device vs the 2-device QR — almost never for a phone-only flow
QR cross-device and FIDO CDA require a **second screen** → friction score ~14 / ~10 vs ~4 for the one-device blades (Stage 1). They only make sense when the **prover runs on a desktop and the phone authorizes it**. For REP's phone-only "connect account," QR is **pure overhead** — exclude it from the happy path; keep it only for a future desktop prover.

## 5. Platform autofill — make the cold/OTP fallback ~1 tap, not copy-paste
When you *must* fall to an OTP (cold, no app, no warm session), autofill keeps it near one tap:
- **iOS Security Code AutoFill:** field `textContentType = .oneTimeCode` (web `autocomplete="one-time-code"`) → the SMS code surfaces in the QuickType bar, **one tap, no typing**, ~3-min window. **Domain-bound codes** (`@example.com #123456`) only autofill on that domain — anti-phishing ([Apple](https://developer.apple.com/documentation/security/one-time-codes)).
- **Android SMS Retriever** (fully **silent, 0 taps**; needs the 11-char app hash + controlled message format) or **SMS User Consent** (**1 tap**, no `READ_SMS` permission, when you don't control the SMS) ([Google](https://developers.google.com/identity/sms-retriever/overview)).
- **Passkeys first-class:** iOS **conditional UI** surfaces a passkey in the QuickType bar (1 tap + Face ID); Android **Credential Manager** unifies passkeys + Sign-in-with-Google + saved passwords in one bottom sheet (1 tap + biometric) ([Android](https://developer.android.com/identity/credential-manager)).

## The playbook in one line
**Connect via `ASWebAuthenticationSession` (iOS) / Custom Tabs (Android) to inherit the system-browser session; never embed login in a `WKWebView`/`WebView`; return via custom scheme (iOS) / App Links (Android); reserve QR for desktop; and back the cold path with Security Code AutoFill / SMS Retriever / passkey-AutoFill so even the fallback is ~1 tap.**
