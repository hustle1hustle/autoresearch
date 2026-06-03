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

        let pkce = PKCE.generate()
        let state = UUID().uuidString
        var comps = URLComponents(string: Config.githubAuthorizeURL)!
        comps.queryItems = [
            .init(name: "client_id", value: Config.githubClientID),
            .init(name: "redirect_uri", value: Config.githubRedirectURI),
            .init(name: "scope", value: Config.githubScope),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
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
        guard let access = items.first(where: { $0.name == "access_token" })?.value else {
            throw AuthError.denied   // raw `code` came back → backend must exchange it first
        }
        let refresh = items.first(where: { $0.name == "refresh_token" })?.value
        let expires = Int(items.first(where: { $0.name == "expires_in" })?.value ?? "28800") ?? 28800
        return OAuthTokens(accessToken: access, refreshToken: refresh, expiresIn: expires)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
}
