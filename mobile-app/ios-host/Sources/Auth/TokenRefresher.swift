import Foundation

/// Exchanges a refresh token for a fresh access token (the "silent grant" in
/// Hack 2). The real exchange happens server-side (client secret off-device) —
/// `GitHubRefresher` (later) POSTs the REP backend; `MockRefresher` simulates it.
protocol TokenRefresher {
    func refresh(_ tokens: OAuthTokens, platform: String) async throws -> OAuthTokens
}

final class MockRefresher: TokenRefresher {
    func refresh(_ tokens: OAuthTokens, platform: String) async throws -> OAuthTokens {
        try await Task.sleep(nanoseconds: 150_000_000)   // simulate the network hop
        return OAuthTokens(accessToken: "gho_mock_refreshed_\(Int(Date().timeIntervalSince1970))",
                           refreshToken: tokens.refreshToken, expiresIn: 28800)
    }
}

enum Refresher {
    static func make() -> TokenRefresher {
        // if !Config.useMockAuth { return GitHubRefresher() }   // backend exchange
        return MockRefresher()
    }
}
