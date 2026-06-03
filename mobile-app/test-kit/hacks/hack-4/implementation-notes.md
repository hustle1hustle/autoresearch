# Hack 4 — Universal Link Auto-Return. Implementation Notes

**Что делает.** Конфигурирует OAuth redirect URI как Universal Link (iOS) / App Link (Android). После OAuth iOS/Android **автоматически** маршрутизирует callback в host-shell. Никаких custom URL schemes, никакого ручного swipe-back.

**Источник.** [Plaid Link iOS docs](https://plaid.com/docs/link/ios/) — "Plaid uses **Universal Links** for secure OAuth redirects rather than custom URL schemes". См. `../../mobile-ux-deep-research.md` §1 Hack 4.

**Где живёт.** Backend (AASA / assetlinks.json hosting) + host-shell (entitlement / manifest + URL handler).

## iOS implementation

### Step 1. Host AASA file

Backend hosts `https://rep.xyz/.well-known/apple-app-site-association`:

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["TEAMID.com.rep.app"],
        "components": [
          { "/": "/oauth/github/callback*" },
          { "/": "/oauth/strava/callback*" },
          { "/": "/oauth/duolingo/callback*" }
        ]
      }
    ]
  }
}
```

- **No file extension** (`apple-app-site-association`, не `.json`)
- **Content-Type. application/json**
- **HTTPS only**, не self-signed cert
- **No redirects** when iOS fetches it
- iOS 14+. Apple's CDN кеширует. Используй mode=developer query param если debug

### Step 2. Add entitlement в Xcode

`com.apple.developer.associated-domains`:

```xml
<key>com.apple.developer.associated-domains</key>
<array>
  <string>applinks:rep.xyz</string>
</array>
```

В debug builds можно добавить `?mode=developer` для skip CDN cache.

### Step 3. Handle URL в app

```swift
@main
struct RepApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    Task { await handleUniversalLink(url) }
                }
                // ИЛИ для NSUserActivity:
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    Task { await handleUniversalLink(url) }
                }
        }
    }

    func handleUniversalLink(_ url: URL) async {
        guard url.host == "rep.xyz" else { return }

        switch url.path {
        case let p where p.hasPrefix("/oauth/github/callback"):
            await GitHubOAuth.handleCallback(url)
        case let p where p.hasPrefix("/oauth/strava/callback"):
            await StravaOAuth.handleCallback(url)
        default:
            break
        }
    }
}
```

### Step 4. OAuth flow uses HTTPS redirect

В OAuth setup (GitHub OAuth app etc):
- **Redirect URI.** `https://rep.xyz/oauth/github/callback`
- **NOT.** `rep://oauth/github/callback` ← это custom scheme, не используй

### Step 5. ASWebAuthenticationSession callback

```swift
let session = ASWebAuthenticationSession(
    url: githubAuthURL,
    callbackURLScheme: nil  // ← nil! Это сигнал что callback это Universal Link
) { url, error in
    // ASWebAuthSession поймает Universal Link callback автоматически
}
session.presentationContextProvider = self
session.start()
```

**Альтернатива.** Использовать `callback: ASWebAuthenticationSession.Callback.https(host:path:)` (iOS 17.4+) явно:

```swift
let session = ASWebAuthenticationSession(
    url: githubAuthURL,
    callback: .https(host: "rep.xyz", path: "/oauth/github/callback")
) { ... }
```

## Android implementation

### Step 1. Host assetlinks.json

Backend hosts `https://rep.xyz/.well-known/assetlinks.json`:

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.rep.app",
      "sha256_cert_fingerprints": ["XX:XX:XX:..."]  // ← из release keystore
    }
  }
]
```

### Step 2. Manifest intent-filter

```xml
<activity android:name=".OAuthCallbackActivity"
          android:exported="true">
    <intent-filter android:autoVerify="true">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="https" />
        <data android:host="rep.xyz" />
        <data android:pathPrefix="/oauth/" />
    </intent-filter>
</activity>
```

`android:autoVerify="true"` — Android проверит assetlinks.json при установке и зарегистрирует app как handler.

### Step 3. Handle intent

```kotlin
class OAuthCallbackActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val url = intent.data ?: run { finish(); return }
        lifecycleScope.launch {
            when {
                url.path?.startsWith("/oauth/github/callback") == true -> {
                    GitHubOAuth.handleCallback(url)
                }
                url.path?.startsWith("/oauth/strava/callback") == true -> {
                    StravaOAuth.handleCallback(url)
                }
            }
            // Возвращаемся в main activity
            startActivity(Intent(this@OAuthCallbackActivity, MainActivity::class.java))
            finish()
        }
    }
}
```

### Step 4. Verify App Links

После install:
```bash
adb shell pm get-app-links com.rep.app
# Должно показать: rep.xyz: verified
```

Если "rejected" — assetlinks.json broken (wrong fingerprint, wrong package, не доступен).

## Edge cases

### TestFlight AASA delay

iOS sometimes fetches AASA late после TestFlight install (до 15 минут). См. `../../open-questions.md` Q6. Workaround. fallback web-страница на callback URL:

`https://rep.xyz/oauth/github/callback` если открывается в Safari (АА не fetched ещё), показывает:

```html
<!DOCTYPE html>
<html>
<head><meta http-equiv="refresh" content="0;url=rep://oauth/github/callback?code=..." /></head>
<body>
  <h1>Opening REP...</h1>
  <p>If REP didn't open automatically, <a href="rep://oauth/github/callback?...">tap here</a>.</p>
</body>
</html>
```

Custom URL scheme `rep://` это **TestFlight-only fallback**, не production primary.

### `Entitlements-Release.plist` missing

Классический баг. AASA работает в debug build, ломается в release потому что Release entitlements не обновлены. Always verify. `codesign -d --entitlements - <app.app>` показывает actual entitlements.

### CDN cache на private servers

iOS 14+ fetches AASA через Apple CDN. Если ваш сервер за VPN/firewall — CDN не доступится. Используйте `applinks:rep.xyz?mode=developer` в debug builds + Developer Mode → Associated Domain Development в Settings → Developer.

## Что НЕ делать

- **Не используй custom URL schemes как primary.** `rep://oauth/...` — любая аппка может объявить такой scheme. Phishing risk.
- **Не делай callback URL который ведёт на login page если app не открылся.** Если AASA fetch failed → юзер в Safari на странице с form'ой login → confusion → abandon.
- **Не игнорируй entitlement в release build.** Test the release flow, не только debug.

## Совместимость

- **Hack 1** ортогонален
- **Hack 2** prerequisite. без working Universal Link нет первого proof'а с saved refresh token
- **Hack 3** ортогонален (pre-sheet ДО, Universal Link ПОСЛЕ)
- **Hack 5** ортогонален
- **Hack 6** ортогонален (notarize-in-animation после Universal Link return)
