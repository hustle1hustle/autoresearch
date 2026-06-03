import Foundation
import AuthenticationServices

/// Real GitHub OAuth via `ASWebAuthenticationSession` with an **HTTPS
/// (Universal Link) callback** — never a custom scheme (Hack 4 / anti-goal).
/// Used when `Config.useMockAuth == false`. The REP backend exchanges the
/// `code` server-side (client secret stays off-device) and 302s back to the
/// callback with scoped, short-lived tokens, which we read off the return URL.
///
/// Shares Safari cookies (`prefersEphemeralWebBrowserSession = false`) so a
/// warm GitHub session skips the login form.
final class GitHubOAuth: NSObject, AuthProviding, ASWebAuthenticationPresentationContextProviding {
    private var anchor: ASPresentationAnchor = ASPresentationAnchor()

    func authenticate(anchor: ASPresentationAnchor,
                      onStage: @escaping (String) -> Void) async throws -> OAuthTokens {
        self.anchor = anchor
        guard Config.githubClientID != "REPLACE_WITH_GITHUB_OAUTH_CLIENT_ID" else {
            throw AuthError.misconfigured
        }
        guard #available(iOS 17.4, *) else { throw AuthError.needsIOS174 }

        // GitHub App user-to-server flow: no `scope` query (scopes come from the
        // App's user permissions). The REP backend does the code→token exchange
        // (client secret off-device) and 302s tokens back to the callback.
        let state = UUID().uuidString
        var comps = URLComponents(string: Config.githubAuthorizeURL)!
        comps.queryItems = [
            .init(name: "client_id", value: Config.githubClientID),
            .init(name: "redirect_uri", value: Config.githubRedirectURI),
            .init(name: "state", value: state),
        ]
        let authURL = comps.url!

        onStage("webauth.opened")
        let callbackURL: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callback: .https(host: Config.appLinkHost, path: Config.oauthCallbackPath)
            ) { url, error in
                if let url {
                    cont.resume(returning: url)
                } else if let error {
                    let ns = error as NSError
                    if ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        cont.resume(throwing: AuthError.cancelled)
                    } else {
                        cont.resume(throwing: error)
                    }
                } else {
                    cont.resume(throwing: AuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false   // share Safari cookies (warm)
            session.start()
        }
        onStage("webauth.universalLinkReturn")

        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw AuthError.denied }
        // CSRF: the returned state must match what we sent.
        if let returned = items.first(where: { $0.name == "state" })?.value, returned != state {
            throw AuthError.denied
        }
        // Code → tokens via the REP backend (client secret stays off-device).
        return try await exchangeCodeForTokens(code: code)
    }

    private func exchangeCodeForTokens(code: String) async throws -> OAuthTokens {
        var req = URLRequest(url: URL(string: Config.githubExchangeURL)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["code": code])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = j["access_token"] as? String else { throw AuthError.denied }
        return OAuthTokens(accessToken: access,
                           refreshToken: j["refresh_token"] as? String,
                           expiresIn: j["expires_in"] as? Int ?? 28800)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
}
