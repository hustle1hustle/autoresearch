import Foundation

/// Single place to flip mock ↔ real and set backend/OAuth values.
/// ①–④ ship with both mocks ON so the opening UX runs on the simulator with
/// zero dependency on the Rust prover or a live OAuth app.
enum Config {
    // MARK: Mock switches (flip as backend/OAuth come online)
    /// Reads an env var (set it in the Xcode scheme ▸ Run ▸ Arguments ▸
    /// Environment Variables) with a fallback — so you flip mock→real and set
    /// URLs/credentials WITHOUT editing this file.
    private static func env(_ key: String) -> String? {
        let v = ProcessInfo.processInfo.environment[key]
        return (v?.isEmpty == false) ? v : nil
    }

    /// Set USE_MOCK_PROVER=false and USE_MOCK_AUTH=false in the scheme to go real.
    static let useMockProver = (env("USE_MOCK_PROVER") ?? "true").lowercased() != "false"
    static let useMockAuth   = (env("USE_MOCK_AUTH") ?? "true").lowercased() != "false"

    // MARK: GitHub (used when useMockAuth = false)
    // IMPORTANT: register as a **GitHub App**, NOT a classic OAuth App — refresh
    // tokens (needed for Hack 2) only work with GitHub Apps (test-kit/setup/
    // 02-oauth-apps.md §A). Client ID looks like "Iv1.…". Scopes come from the
    // App's *user permissions*, not a `scope` query param. The code→token
    // exchange + refresh run on the REP backend (client secret never ships in
    // the app); the backend 302s the resulting tokens back to the callback.
    static let githubClientID = env("GITHUB_CLIENT_ID") ?? "REPLACE_WITH_GITHUB_APP_CLIENT_ID"  // Iv1.…
    /// DEBUG-ONLY shortcut: if GITHUB_CLIENT_SECRET is set in the scheme, the app
    /// exchanges the code DIRECTLY with GitHub — so your FIRST real proof needs no
    /// backend at all. PRODUCTION must leave this unset and use the backend
    /// (the secret must never ship in a release build).
    static let githubClientSecret = env("GITHUB_CLIENT_SECRET")
    /// HTTPS callback (Universal Link, Hack 4) — never a custom scheme.
    static let githubRedirectURI = "https://r3p.xyz/oauth/github/callback"
    static let githubAuthorizeURL = "https://github.com/login/oauth/authorize"
    /// REP backend (mobile-app/backend-stub) — holds the client secret. Set
    /// BACKEND_URL in the scheme (e.g. https://rep-oauth.fly.dev or http://<mac-ip>:8787).
    private static let backendBase = env("BACKEND_URL") ?? "https://r3p.xyz"
    static let githubExchangeURL = backendBase + "/api/oauth/github/exchange"
    static let githubRefreshURL  = backendBase + "/api/oauth/github/refresh"

    // MARK: TLSN / verifier
    /// Matches the app's Settings "Verifier URL". demo.tlsnotary.org to start;
    /// for a real-device GitHub proof you need a notary that allow-lists
    /// api.github.com (OQ8 — self-host tlsnotary/notary-server, or r3p.xyz).
    static let verifierURL = URL(string: env("VERIFIER_URL") ?? "https://demo.tlsnotary.org")!
    /// Default proving mode. Proxy ~1–2s; flip to .mpc on 403/WAF (ModeRouter).
    static let defaultMode: ProverMode = .proxy

    // MARK: Universal Links (Hack 4)
    static let appLinkHost = "r3p.xyz"
    static let oauthCallbackPath = "/oauth/github/callback"

    // MARK: UX timing
    /// If notarize exceeds this, swap the hidden-under-animation path (Hack 6)
    /// for the explicit StageProgress UI. Never show a bare "Loading…".
    static let notarizeAnimationBudget: TimeInterval = 2.0
}
