# 06 — First Proof Walkthrough (zero to success на твоём iPhone)

**Когда нужно.** После того как сделал 01-05. этот гайд связывает всё вместе в один end-to-end run.

**Что получишь.** Working first proof on real iPhone за ~30 минут. GitHub contributions notarized + saved + visible в host-shell.

**Время.** ~30 минут (без 01-05 setup time)

**Prerequisites.**
- Завершены 01-04 (xcframework, OAuth apps, notary deployed, AASA hosted)
- iPhone подключен к Mac через USB или WiFi для Xcode debugging
- iCloud Keychain enabled на тестовом iPhone

---

## Phase 1. Setup verify (5 минут)

Перед prototype running проверь что все building blocks готовы.

### 1.1 xcframework

```bash
ls mobile-app/test-kit/tlsn-build/ios/
# должно содержать:
# TlsnProver.xcframework/
# TlsnProver.swift
```

Если нет → вернись к [01-xcframework-build.md](01-xcframework-build.md).

### 1.2 OAuth app credentials

```bash
# В secure storage. твой password manager
echo "GitHub OAuth Client ID: $(cat ~/secrets/github_oauth_client_id)"  # должен output что-то
```

Если нет → [02-oauth-apps.md](02-oauth-apps.md).

### 1.3 Notary running

```bash
curl -k https://verifier.rep.xyz/health
# Или для local dev:
# curl -k https://localhost:7047/health
```

Должен return 200 OK. Если не работает → [03-self-hosted-notary.md](03-self-hosted-notary.md).

### 1.4 AASA fetched

```bash
curl -i https://rep.xyz/.well-known/apple-app-site-association
# Content-Type: application/json
# 200 OK
# Body: правильный JSON с твоим Bundle ID
```

Если нет → [04-universal-links.md](04-universal-links.md).

### 1.5 Xcode project ready

Project should:
- Минимум iOS 17.0 deployment target
- Bundle ID matches AASA (`com.rep.app` или whatever ты задал)
- Associated Domains capability enabled с `applinks:rep.xyz` и `webcredentials:rep.xyz`
- `TlsnProver.xcframework` linked, "Embed & Sign"

---

## Phase 2. Build minimal host-shell (15 минут)

Если ты следуешь PLAN.md items ①-③, у тебя уже большая часть готова. Если нет — здесь minimal scaffolding:

### 2.1 Project structure

```
RepApp/
├── RepApp.swift              ← App entry point
├── Models/
│   ├── PKCE.swift            ← code_verifier + challenge generation
│   ├── ProofClaim.swift      ← VCC structure
│   └── KeychainHelper.swift  ← refresh token storage (Hack 2)
├── Networking/
│   ├── GitHubOAuth.swift     ← code exchange + refresh grant
│   └── ProverSession.swift   ← wraps TlsnProver xcframework
├── Views/
│   ├── EntryView.swift       ← list of platforms / "Add proof"
│   ├── ConnectGitHubView.swift  ← OAuth handoff + Hack 1+3+6
│   └── SuccessView.swift     ← post-proof + "What was proved" expandable
└── Resources/
    └── Info.plist            ← Bundle ID + URL schemes (fallback) + LSApplicationQueriesSchemes (Hack)
```

### 2.2 PKCE.swift

```swift
import Foundation
import CryptoKit

struct PKCE {
    let verifier: String
    let challenge: String

    static func generate() -> PKCE {
        let verifier = UUID().uuidString + UUID().uuidString  // 72 chars min
        let data = verifier.data(using: .utf8)!
        let hash = SHA256.hash(data: data)
        let challenge = Data(hash).base64URLEncodedString()
        return PKCE(verifier: verifier, challenge: challenge)
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

### 2.3 GitHubOAuth.swift (минимальный)

```swift
import Foundation
import AuthenticationServices

@MainActor
class GitHubOAuth: NSObject {
    static let clientID = "Iv1.YOUR_CLIENT_ID"
    static let redirectURI = "https://rep.xyz/oauth/github/callback"
    static let scope = "read:user"

    static func authorizationURL(pkce: PKCE, state: String) -> URL {
        var components = URLComponents(string: "https://github.com/login/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return components.url!
    }

    /// Exchange code → access_token + refresh_token
    /// ⚠️ Production. ходить через свой backend чтобы скрыть client_secret.
    /// Для dev. возможно ходить напрямую (БУДЕТ leak client_secret через bundle).
    static func exchangeCode(_ code: String, pkce: PKCE) async throws -> (accessToken: String, refreshToken: String?) {
        // ВНИМАНИЕ. Для production используй свой server endpoint
        // POST https://rep.xyz/api/oauth/github/exchange
        // который owns client_secret и proxies request

        // Dev/test version (ходит напрямую к GitHub, использует client_secret):
        // НЕ EMBED CLIENT_SECRET в production app

        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int?
            let refresh_token_expires_in: Int?
            let scope: String?
            let token_type: String?
        }

        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id": clientID,
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": pkce.verifier,
            // "client_secret": "...",  ← для GitHub App не нужен с PKCE  
        ].map { "\($0.key)=\($0.value)" }.joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)

        return (response.access_token, response.refresh_token)
    }
}
```

### 2.4 ProverSession.swift (wrapper around xcframework)

```swift
import Foundation
import TlsnProver  // from xcframework

@MainActor
class ProverSession {
    let inner: TlsnProver  // xcframework type

    init() throws {
        self.inner = try TlsnProver.initialize()
    }

    func proveGitHub(accessToken: String) async throws -> Proof {
        // Build the GraphQL request
        let query = """
        query { viewer { login contributionsCollection(from: "2026-01-01T00:00:00Z") { contributionCalendar { totalContributions } } } }
        """

        let bodyJSON = try JSONSerialization.data(withJSONObject: ["query": query])

        let request = TlsnRequest(
            method: "POST",
            host: "api.github.com",
            path: "/graphql",
            headers: [
                "Authorization": "Bearer \(accessToken)",
                "Content-Type": "application/json",
                "User-Agent": "rep-prover/1.0",
            ],
            body: bodyJSON
        )

        let options = TlsnProveOptions(
            mode: .Proxy,                                            // ← Hero proxy mode
            verifierURL: "wss://verifier.rep.xyz/notary",
            redactHeaders: ["Authorization"],                        // hide bearer
            revealResponse: true,                                    // reveal whole body
        )

        // Hack 6. notarize in background, parallel to UI animation
        return try await inner.prove(request: request, options: options) { progress in
            // Optional. progress callback для stage UI
        }
    }
}
```

(Exact API names и types depend on UniFFI bindgen output — adjust to match generated `TlsnProver.swift`.)

### 2.5 ConnectGitHubView.swift (минимальный)

```swift
import SwiftUI
import AuthenticationServices

struct ConnectGitHubView: View {
    @State private var prover: ProverSession?
    @State private var pkce: PKCE = PKCE.generate()
    @State private var state: ViewState = .idle

    var body: some View {
        VStack(spacing: 24) {
            // ... copy + Continue button ...
            Button("Continue with GitHub") {
                Task { await startOAuthFlow() }
            }
        }
        .task {
            // Hack 1. pre-warm в background
            do {
                self.prover = try ProverSession()
            } catch {
                // Best effort. fall back on tap
            }
        }
    }

    @MainActor
    func startOAuthFlow() async {
        let stateString = UUID().uuidString
        let authURL = GitHubOAuth.authorizationURL(pkce: pkce, state: stateString)

        do {
            let callbackURL = try await ASWebAuthenticationSession.start(
                url: authURL,
                callback: .https(host: "rep.xyz", path: "/oauth/github/callback")
            )

            guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value
            else { throw OAuthError.noCode }

            let (accessToken, refreshToken) = try await GitHubOAuth.exchangeCode(code, pkce: pkce)

            // Hack 2. save refresh token under biometry
            if let refresh = refreshToken {
                try KeychainHelper.save(refresh, service: "github.refresh", biometryRequired: true)
            }

            // Hack 6. notarize in background while transition animation runs
            state = .notarizing
            let proof = try await prover?.proveGitHub(accessToken: accessToken)

            state = .success(proof!)
        } catch {
            state = .error(error)
        }
    }
}

enum ViewState {
    case idle, notarizing, success(Proof), error(Error)
}
```

(Note. это **minimal** prototype, не production. Hack 3 pre-sheet, full Hack 6 timing, anti-pattern fixes etc — следуй полному SPEC.md.)

---

## Phase 3. Run on device (5 минут)

### 3.1 Connect iPhone

USB or WiFi (if paired). Xcode → Window → Devices and Simulators → iPhone должен appear.

### 3.2 Select device target

В Xcode top bar. select your iPhone as run destination (not simulator).

### 3.3 Build & Run

⌘R. Xcode builds, signs, installs, launches.

Если **"Untrusted Developer"** на iPhone:
- Settings → General → VPN & Device Management → tap твой developer profile → Trust

### 3.4 Trigger first proof

1. Tap "Connect GitHub" в app
2. Watch для:
   - ✅ Хак 1. WebSocket connected message в Xcode console (`notarize.websocketConnected stage=prewarm`)
   - ✅ Хак 3. pre-sheet appears (если имплементировал)
   - ✅ Стандарт. iOS consent sheet "App wants to use github.com to Sign In"
   - Tap Continue
3. Safari opens GitHub OAuth page
4. Tap "Authorize REP"
5. ✅ Хак 4. iOS auto-returns to app (no Safari swipe-back)
6. ✅ Хак 6. notarize fires в background, success appears within ~1-2 секунды
7. ✅ Хак 2 setup. refresh token saved to Keychain (verify в Console.app filter `com.rep.github.refresh`)

### 3.5 Verify proof artifact

В success state:
- Tap "What was proved" expandable
- Should show. notarized request body, revealed response fields, notary public key, expiry date

### 3.6 Test repeat (Hack 2 verification)

1. Force-quit app
2. Re-open
3. Tap "Prove again" на GitHub row
4. ✅ Face ID prompt
5. Look at phone
6. ✅ Proof regenerated в ~3-4 секунды без OAuth dance

→ Если шаги 3.4 и 3.6 работают — **all 6 hacks operational**. Победа.

---

## Phase 4. Measurement (5 минут)

### 4.1 Stopwatch критичные numbers

Используй stopwatch (physical or Apple Watch) для измерения:

| Metric | Tap point | Stop point | Target |
|---|---|---|---|
| Warm-first total | Tap "Connect GitHub" | Success state shown | ≤ 10s |
| Warm-returning total | Tap "Prove again" | Success state shown | ≤ 4s |
| Cold total | Tap "Connect GitHub" (no GitHub Safari login) | Success state shown | ≤ 30s |

Записывай 3 attempts per scenario, take median.

### 4.2 Update comparison CSV

```bash
open mobile-app/test-kit/comparison/template.csv
```

Заполни первые 3 rows (warm-returning, warm-first, cold × github) для `all_stacked` column.

### 4.3 Anti-patterns check

Прогон `mobile-app/test-kit/ANTI-PATTERNS-CHECKLIST.md` против своего prototype. 10 checks, должны быть все ✓.

---

## Common pitfalls

### "Untrusted Developer" блокирует app

Settings → General → VPN & Device Management → trust developer profile.

### Notary connection refused

- Verify notary running. `docker-compose ps`
- Verify URL accessible from device. (если local notary, iPhone и Mac должны быть в одной WiFi)
- Use ngrok для quick test. `ngrok http 7047`, обнови `verifierURL` в Swift code

### OAuth state mismatch

Сохранил state в memory, app restarted, state lost. Solution. persist state в Keychain или UserDefaults между OAuth start и callback.

### Refresh token не приходит

OAuth App вместо GitHub App. См. [02-oauth-apps.md § A](02-oauth-apps.md#a-github-oauth-app-hero).

### Universal Link не auto-return

Чаще всего AASA не fetched. См. [04-universal-links.md § Common pitfalls](04-universal-links.md#common-pitfalls).

### "Notarize timeout"

Notary не reachable или endpoint не whitelisted. Verify в notary logs. `docker logs rep-notary`.

### Face ID prompt не появляется

Keychain item saved без `.biometryCurrentSet` flag. Re-check `KeychainHelper.save` implementation. Use the snippet from [`hacks/hack-2/implementation-notes.md`](../hacks/hack-2/implementation-notes.md).

---

## Что обновить после первого успешного proof

1. **`test-kit/open-questions.md`.** все 5 Q's должны быть RESOLVED. Document outcomes.
2. **`test-kit/comparison/template.csv`.** заполни row для warm-first GitHub.
3. **`spec/SPEC.md`.** если нашёл deviation от spec в реальности — flag in comments или раздели PR.
4. **`troubleshooting.md`.** добавь any new failure modes которые встретил.
5. **Demo video / screenshot.** record first success для PM presentation.

---

## Verify готов to next steps

✅ Первый proof минтится на real iPhone
✅ Repeat proof работает в 1 тап через Face ID
✅ Comparison CSV первый row заполнен
✅ Anti-patterns checklist passes

→ Готов к Phase 4 в RUN-ORDER.md. остальные 6 Tier-1 targets.

---

## Если что-то не работает после 30 минут

Не борись с ним 2 часа в одиночку. Открой issue или ping PM. Конкретные signals что нужна помощь:

- Notary cannot be deployed (infrastructure issue) → DevOps team
- Universal Link не работает после AASA verified → может быть Apple side issue, file Apple Developer Forum thread
- xcframework build fails → может быть TLSN team bug, file issue в их GitHub
- OAuth flow returns error → может быть OAuth app config issue, re-walk [02-oauth-apps.md](02-oauth-apps.md)

Используй [`../troubleshooting.md`](../troubleshooting.md) как первый stop для common issues.
