import Foundation
import Security

/// Hack 2 — refresh/access tokens in the Keychain, gated by Face ID.
/// Stored under `SecAccessControl(.biometryCurrentSet)` +
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`:
///   • reading prompts Face ID;
///   • re-enrolling Face ID **invalidates** the item (→ `.noItem` → reconnect).
///
/// Works on the iOS Simulator with Face ID enrolled
/// (Features ▸ Face ID ▸ Enrolled, then "Matching Face") — so the warm-returning
/// 1-tap path is testable now even with mock tokens.
enum TokenLoadResult: Equatable {
    case found(OAuthTokens)
    case noItem          // never saved, or invalidated by biometry re-enrollment
    case biometryFailed  // user cancelled / Face ID failed

    static func == (l: TokenLoadResult, r: TokenLoadResult) -> Bool {
        switch (l, r) {
        case (.noItem, .noItem), (.biometryFailed, .biometryFailed): return true
        case let (.found(a), .found(b)): return a.accessToken == b.accessToken
        default: return false
        }
    }
}

final class KeychainTokenStore: TokenStore {
    static let shared = KeychainTokenStore()
    private let service = "xyz.r3p.host.tokens"

    private struct Stored: Codable {
        let accessToken: String; let refreshToken: String?; let expiresIn: Int
        init(_ t: OAuthTokens) { accessToken = t.accessToken; refreshToken = t.refreshToken; expiresIn = t.expiresIn }
        var tokens: OAuthTokens { OAuthTokens(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn) }
    }

    private func baseQuery(_ platform: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: platform]
    }

    /// Writing does not prompt Face ID (only reading does for biometryCurrentSet).
    func save(_ tokens: OAuthTokens, platform: String) {
        guard let data = try? JSONEncoder().encode(Stored(tokens)) else { return }
        SecItemDelete(baseQuery(platform) as CFDictionary)
        var add = baseQuery(platform)
        add[kSecValueData as String] = data
        if let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, nil) {
            add[kSecAttrAccessControl as String] = access
        }
        SecItemAdd(add as CFDictionary, nil)
    }

    /// Synchronous protocol method — biometric items can't be read without a
    /// prompt, so this always returns nil. Use `loadWithBiometry` instead.
    func load(platform: String) -> OAuthTokens? { nil }

    /// Reads the token, prompting Face ID. Runs off the main thread.
    func loadWithBiometry(platform: String, reason: String) async -> TokenLoadResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var q = self.baseQuery(platform)
                q[kSecReturnData as String] = true
                q[kSecMatchLimit as String] = kSecMatchLimitOne
                q[kSecUseOperationPrompt as String] = reason
                var item: CFTypeRef?
                let status = SecItemCopyMatching(q as CFDictionary, &item)
                switch status {
                case errSecSuccess:
                    if let data = item as? Data, let s = try? JSONDecoder().decode(Stored.self, from: data) {
                        cont.resume(returning: .found(s.tokens))
                    } else {
                        cont.resume(returning: .noItem)
                    }
                case errSecItemNotFound:
                    cont.resume(returning: .noItem)
                case errSecUserCanceled, errSecAuthFailed:
                    cont.resume(returning: .biometryFailed)
                default:
                    cont.resume(returning: .biometryFailed)
                }
            }
        }
    }

    func clear(platform: String) { SecItemDelete(baseQuery(platform) as CFDictionary) }
}
