# 04 — Universal Links (AASA hosting + entitlement + testing)

**Когда нужно.** Item ③ PLAN.md. Hack 4 (Universal Link auto-return) — критичен для OAuth callback handling.

**Что получишь.** AASA file hosted, entitlement в Xcode project, working auto-return из ASWebAuthenticationSession.

**Время.** ~30-60 минут first time (включая DNS / hosting setup), ~5 минут для config changes.

**Prerequisites.**
- Domain (e.g. `r3p.xyz`) с control над `/.well-known/` path
- Apple Developer team (бесплатный Apple ID работает для simulator, paid нужен для prod entitlements)
- Bundle ID для iOS app (e.g. `com.rep.app` или `xyz.rep.app`)

---

## Steps

### 1. Setup hosting для `r3p.xyz`

Любой web host где ты можешь serve файлы под `/.well-known/`. Options:

#### Option A. GitHub Pages (free, easy)

```bash
# Create a repo "r3p.xyz" с CNAME file
mkdir -p .well-known
echo "r3p.xyz" > CNAME
git init && git add . && git commit -m "initial"
# push to github.com/<user>/r3p.xyz
# Pages settings → enable, custom domain r3p.xyz
```

DNS. CNAME `r3p.xyz` → `<user>.github.io`.

#### Option B. Cloudflare Pages / Vercel / Netlify

Standard static hosting. Деплой папку с `.well-known/` файлом.

#### Option C. Backend server

Если у вас есть REP API server. add static route:
```
GET /.well-known/apple-app-site-association → static file
```

### 2. Создай AASA file

**File path.** `https://r3p.xyz/.well-known/apple-app-site-association`

⚠️ **No `.json` extension.** Just `apple-app-site-association`.

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["TEAMID.com.rep.app"],
        "components": [
          { "/": "/oauth/github/callback*", "comment": "GitHub OAuth callback" },
          { "/": "/oauth/strava/callback*", "comment": "Strava OAuth callback" },
          { "/": "/oauth/stackoverflow/callback*", "comment": "StackOverflow OAuth callback" },
          { "/": "/p/*", "comment": "Shared proof deep links" }
        ]
      }
    ]
  },
  "webcredentials": {
    "apps": ["TEAMID.com.rep.app"]
  }
}
```

**Substitute.**
- `TEAMID` → твой Apple Developer Team ID (находится в Apple Developer portal → Membership)
- `com.rep.app` → твой actual Bundle ID

### 3. Verify AASA serves correctly

```bash
# Должно return JSON
curl -i https://r3p.xyz/.well-known/apple-app-site-association

# Headers must include:
# Content-Type: application/json
# (или application/pkcs7-mime для signed AASA, но это для enterprise)

# NO redirects allowed. Если статус 301/302 — Apple не fetch'нет
```

#### Common server config

**nginx:**
```nginx
location /.well-known/apple-app-site-association {
    default_type application/json;
    try_files $uri =404;
}
```

**Express.js:**
```js
app.get('/.well-known/apple-app-site-association', (req, res) => {
    res.type('application/json');
    res.sendFile(path.join(__dirname, 'static', 'apple-app-site-association'));
});
```

**Cloudflare Pages.** Just put the file at `public/.well-known/apple-app-site-association`. Should auto-serve.

### 4. Add entitlement в Xcode project

**File.** `<YourApp>.entitlements` (создан Xcode automatically когда ты enable Associated Domains capability).

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTD/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.associated-domains</key>
    <array>
        <string>applinks:r3p.xyz</string>
        <string>webcredentials:r3p.xyz</string>
    </array>
</dict>
</plist>
```

**В Xcode UI.**
1. Project navigator → tap project → tap target → Signing & Capabilities tab
2. Tap `+ Capability` → Associated Domains
3. Tap `+` под Associated Domains
4. Add `applinks:r3p.xyz`
5. Add `webcredentials:r3p.xyz`

### 5. Dev mode для debugging

Для testing БЕЗ requiring real domain (development build):

В entitlement file:
```xml
<string>applinks:r3p.xyz?mode=developer</string>
```

И на iOS device. **Settings → Developer → Associated Domain Development** enable.

Затем:
```bash
# В Terminal на Mac connected to device:
swcutil developer-mode -e true
```

Это bypass'ит Apple CDN cache и fetches AASA напрямую (faster iteration).

### 6. Handle URL в SwiftUI App

```swift
@main
struct RepApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    Task { await handleUniversalLink(url) }
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    Task { await handleUniversalLink(url) }
                }
        }
    }

    func handleUniversalLink(_ url: URL) async {
        guard url.host == "r3p.xyz" else { return }

        switch url.path {
        case let path where path.hasPrefix("/oauth/github/callback"):
            await GitHubOAuth.handleCallback(url)
        case let path where path.hasPrefix("/oauth/strava/callback"):
            await StravaOAuth.handleCallback(url)
        case let path where path.hasPrefix("/oauth/stackoverflow/callback"):
            await StackOverflowOAuth.handleCallback(url)
        case let path where path.hasPrefix("/p/"):
            await deepLinkProofView(url)
        default:
            break
        }
    }
}
```

### 7. Wire ASWebAuthenticationSession

```swift
import AuthenticationServices

class GitHubOAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Find the key window
        return UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }

    func startGitHubOAuth(pkce: PKCE) async throws -> URL {
        let authURL = makeAuthURL(pkce: pkce)

        return try await withCheckedThrowingContinuation { continuation in
            // iOS 17.4+ syntax. callback as Universal Link
            let session = ASWebAuthenticationSession(
                url: authURL,
                callback: .https(host: "r3p.xyz", path: "/oauth/github/callback")
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = callbackURL {
                    continuation.resume(returning: url)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false  // ← cookies share (Hack 3 territory)
            session.start()
        }
    }
}
```

**Alternative для iOS 17.3-**:
```swift
let session = ASWebAuthenticationSession(
    url: authURL,
    callbackURLScheme: nil  // nil sygnal'ит что callback это Universal Link
) { ... }
```

---

## Testing

### Quick test. Browser → app

1. Установи app на device (через Xcode или TestFlight)
2. Wait 2 минуты для AASA fetch
3. На device. open Safari, paste `https://r3p.xyz/oauth/github/callback?test=1`
4. Если правильно настроено → Safari banner "Open in REP" appears OR app opens automatically

Если не работает:

#### Verify AASA fetched

В iOS Settings → Developer → Associated Domain Development → Enable. Then:

```bash
# в Terminal Mac connected to device:
swcutil show
```

Должно показать. `applinks:r3p.xyz` → `Validated`. Если `Failed` — see error message.

#### Verify entitlement в release build

```bash
codesign -d --entitlements - YourApp.app 2>&1 | grep applinks
# Должно show. <string>applinks:r3p.xyz</string>
```

Если empty в release но present в debug — `Entitlements-Release.plist` нужно update'нуть отдельно (classic bug).

### Full OAuth test

1. Trigger OAuth flow в app:
   ```swift
   let callbackURL = try await GitHubOAuthCoordinator().startGitHubOAuth(pkce: pkce)
   print("Got callback. \(callbackURL)")  // https://r3p.xyz/oauth/github/callback?code=xxx
   ```

2. ASWebAuthenticationSession opens Safari sheet
3. User taps "Continue" в iOS consent sheet (Hack 3 pre-sheet covered separately)
4. Safari shows GitHub OAuth page
5. User taps "Authorize REP"
6. Safari redirects to `https://r3p.xyz/oauth/github/callback?code=xxx&state=xxx`
7. iOS intercepts via AASA → routes to app
8. Sheet collapses, `onOpenURL` fires в host app

If step 7 fails. Universal Link не маршрутизирует. См. troubleshooting ниже.

---

## Common pitfalls

### "Universal Link не маршрутизирует, остаётся в Safari"

Most common причина. AASA не fetched.

Fixes:
1. Verify file accessible. `curl -i https://r3p.xyz/.well-known/apple-app-site-association`
2. Verify Content-Type правильный (application/json)
3. No redirects (status must be 200)
4. Enable Associated Domain Development на device
5. Re-install app (force AASA refresh)
6. Wait 15+ минут (TestFlight delay)

### TestFlight AASA fetch delay

Известная проблема. iOS sometimes fetches AASA лагом до 15 минут после TestFlight install ([Apple Forums](https://developer.apple.com/forums/thread/108339)).

**Workaround.** Add fallback web page at callback URL:

`https://r3p.xyz/oauth/github/callback`. сервер показывает:

```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Opening REP...</title>
    <meta http-equiv="refresh" content="2;url=rep://oauth/github/callback?code=<code>&state=<state>">
</head>
<body style="font-family: -apple-system; padding: 40px; text-align: center;">
    <h1>Opening REP...</h1>
    <p>If REP didn't open automatically:</p>
    <a href="rep://oauth/github/callback?...">Open in REP</a>
</body>
</html>
```

⚠️ Custom URL scheme `rep://` это ONLY fallback. Production app should use Universal Link primary.

### "Entitlement-Release.plist missing applinks"

Xcode иногда updates only Debug entitlements when you add capability via UI.

Fix. open both `Entitlements-Debug.plist` и `Entitlements-Release.plist`, ensure both have `com.apple.developer.associated-domains` with `applinks:r3p.xyz`.

### "Code signing error: associated-domains entitlement is missing"

Free Apple ID не supports Associated Domains. Solutions:
1. Use paid Developer account ($99/year)
2. Use free Apple ID но deploy only via Xcode direct install (not TestFlight)
3. Use developer mode + bypass (хакки, не recommend)

### "Multiple AASA files found"

Apple parses ONE AASA. Если на сервере есть `.json` extension в дополнение к no-extension version — может cause confusion. Stick to `apple-app-site-association` no-extension.

### CDN cache stale (production)

iOS 14+ fetches AASA через Apple CDN. Если ты update'нул AASA file и iOS видит старую версию:

1. Wait 24 hours (CDN TTL)
2. Or bump app version → re-install → forces AASA re-fetch
3. Or use `?mode=developer` в entitlement для bypass (dev only)

---

## Verify готов

1. `curl -i https://r3p.xyz/.well-known/apple-app-site-association` → 200 OK + JSON
2. `swcutil show` на device → `applinks:r3p.xyz` → Validated
3. Manual OAuth test (см. "Full OAuth test" выше) → app opens automatically
4. `onOpenURL` handler fires с правильным URL

→ Готов имплементить Hack 4 в host-shell.

## Что обновить после успешной настройки

1. `test-kit/open-questions.md` → Q3 RESOLVED (Universal Links supported)
2. `test-kit/comparison/template.csv` → начни мерить `universal_link_return_rate` (target > 98%)
3. AASA file под version control (часть mobile-app/ или separate `rep-xyz-static/` repo)
