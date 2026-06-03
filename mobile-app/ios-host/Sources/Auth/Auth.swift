import Foundation
import Combine
import CryptoKit
import AuthenticationServices

struct OAuthTokens { let accessToken: String; let refreshToken: String?; let expiresIn: Int }

enum AuthError: Error { case cancelled, denied, misconfigured, needsIOS174 }

protocol AuthProviding {
    /// Runs the platform login handoff and returns tokens. `onStage` emits
    /// event-spec stage names ("webauth.opened", …). Throws on cancel/denial.
    func authenticate(anchor: ASPresentationAnchor,
                      onStage: @escaping (String) -> Void) async throws -> OAuthTokens
}

/// PKCE (RFC 7636, S256).
struct PKCE {
    let verifier: String
    let challenge: String
    static func generate() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64URLEncodedString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        return PKCE(verifier: verifier, challenge: challenge)
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Simulated handoff for the mock-first opening UX (no Client ID / rep.xyz
/// needed). Mirrors the real stage timing closely enough to feel right.
final class MockAuth: AuthProviding {
    func authenticate(anchor: ASPresentationAnchor,
                      onStage: @escaping (String) -> Void) async throws -> OAuthTokens {
        onStage("webauth.opened")
        try await Task.sleep(nanoseconds: 350_000_000)
        onStage("webauth.systemSheetShown")
        try await Task.sleep(nanoseconds: 250_000_000)
        onStage("webauth.consentApproved")
        onStage("webauth.universalLinkReturn")
        return OAuthTokens(accessToken: "gho_mock", refreshToken: "ghr_mock", expiresIn: 28800)
    }
}

/// Resolves the active auth provider from Config.
enum Auth {
    static func make() -> AuthProviding {
        Config.useMockAuth ? MockAuth() : GitHubOAuth()
    }
}

// MARK: - Token storage

protocol TokenStore {
    func save(_ tokens: OAuthTokens, platform: String)
    func load(platform: String) -> OAuthTokens?
}

/// In-memory for ①–④. Item ⑥ replaces this with Keychain under
/// `SecAccessControl(.biometryCurrentSet)` + `…WhenUnlockedThisDeviceOnly`
/// (Face ID gate; re-enrollment invalidates the item → fall back to full OAuth).
final class InMemoryTokenStore: TokenStore {
    static let shared = InMemoryTokenStore()
    private var store: [String: OAuthTokens] = [:]
    func save(_ tokens: OAuthTokens, platform: String) { store[platform] = tokens }
    func load(platform: String) -> OAuthTokens? { store[platform] }
}

// MARK: - Universal Link routing (Hack 4)

/// Receives the OAuth callback Universal Link from `REPApp.onOpenURL` and hands
/// it to whoever is awaiting the return.
@MainActor
final class UniversalLinkRouter: ObservableObject {
    static let shared = UniversalLinkRouter()
    private var pending: ((URL) -> Void)?

    func awaitCallback(_ handler: @escaping (URL) -> Void) { pending = handler }

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.host == Config.appLinkHost, url.path == Config.oauthCallbackPath else { return false }
        pending?(url); pending = nil
        return true
    }
}
