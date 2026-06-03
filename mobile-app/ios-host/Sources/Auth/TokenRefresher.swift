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

/// Real refresh via the REP backend (which holds the GitHub App client secret;
/// GitHub rotates the refresh token on each use — we store whatever comes back).
final class GitHubRefresher: TokenRefresher {
    func refresh(_ tokens: OAuthTokens, platform: String) async throws -> OAuthTokens {
        guard let refresh = tokens.refreshToken else { throw AuthError.denied }
        var req = URLRequest(url: URL(string: Config.githubRefreshURL)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refresh])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = j["access_token"] as? String else { throw AuthError.denied }
        return OAuthTokens(accessToken: access,
                           refreshToken: j["refresh_token"] as? String ?? refresh,
                           expiresIn: j["expires_in"] as? Int ?? 28800)
    }
}

enum Refresher {
    static func make() -> TokenRefresher {
        Config.useMockAuth ? MockRefresher() : GitHubRefresher()
    }
}
