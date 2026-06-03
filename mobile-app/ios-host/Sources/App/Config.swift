import Foundation

/// Single place to flip mock ↔ real and set backend/OAuth values.
/// ①–④ ship with both mocks ON so the opening UX runs on the simulator with
/// zero dependency on the Rust prover or a live OAuth app.
enum Config {
    // MARK: Mock switches (flip as backend/OAuth come online)
    /// MockProver returns a realistic GitHub result. Flip off in item ⑧ once
    /// the TLSN xcframework + UniFFIProver.swift are in place.
    static let useMockProver = true
    /// MockAuth simulates the OAuth handoff (no real Client ID / rep.xyz needed).
    /// Flip off once you create the GitHub OAuth app + host the callback.
    static let useMockAuth = true

    // MARK: GitHub OAuth (used when useMockAuth = false)
    static let githubClientID = "REPLACE_WITH_GITHUB_OAUTH_CLIENT_ID"
    static let githubScope = "read:user"
    /// HTTPS callback (Universal Link, Hack 4) — never a custom scheme.
    static let githubRedirectURI = "https://rep.xyz/oauth/github/callback"
    static let githubAuthorizeURL = "https://github.com/login/oauth/authorize"

    // MARK: TLSN / verifier
    /// Matches the app's Settings "Verifier URL". demo.tlsnotary.org to start;
    /// for a real-device GitHub proof you need a notary that allow-lists
    /// api.github.com (OQ8 — self-host tlsnotary/notary-server, or rep.xyz).
    static let verifierURL = URL(string: "https://demo.tlsnotary.org")!
    /// Default proving mode. Proxy ~1–2s; flip to .mpc on 403/WAF (ModeRouter).
    static let defaultMode: ProverMode = .proxy

    // MARK: Universal Links (Hack 4)
    static let appLinkHost = "rep.xyz"
    static let oauthCallbackPath = "/oauth/github/callback"

    // MARK: UX timing
    /// If notarize exceeds this, swap the hidden-under-animation path (Hack 6)
    /// for the explicit StageProgress UI. Never show a bare "Loading…".
    static let notarizeAnimationBudget: TimeInterval = 2.0
}
