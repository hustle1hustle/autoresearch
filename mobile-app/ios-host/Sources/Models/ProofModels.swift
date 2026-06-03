import Foundation
import Combine

/// A minted, attested fact stored in the on-device User Context Graph.
struct ProofClaim: Identifiable, Codable, Equatable {
    let id: UUID
    let platform: String        // "github"
    let account: String         // "octocat"
    let predicate: String       // "github.contributions.2026"
    let value: Int              // 1247
    let label: String           // "contributions"
    let mintedAt: Date
    let mode: String            // "proxy"
    let serverName: String      // "api.github.com"
    let revealed: [String]
    let redacted: [String]

    init(platform: String, account: String, value: Int, label: String,
         mode: String, serverName: String, revealed: [String], redacted: [String]) {
        self.id = UUID()
        self.platform = platform
        self.account = account
        self.predicate = "\(platform).contributions.2026"
        self.value = value
        self.label = label
        self.mintedAt = Date()
        self.mode = mode
        self.serverName = serverName
        self.revealed = revealed
        self.redacted = redacted
    }
}

/// On-device store of minted claims (UserDefaults-backed for now; the real
/// graph + share artifact are separate deliverables).
@MainActor
final class ContextGraph: ObservableObject {
    @Published private(set) var claims: [ProofClaim] = []
    private let key = "rep.claims.v1"

    init() { load() }

    func add(_ c: ProofClaim) { claims.insert(c, at: 0); save() }
    func latest(platform: String) -> ProofClaim? { claims.first { $0.platform == platform } }
    var isWarmReturning: Bool { !claims.isEmpty }

    private func load() {
        if let d = UserDefaults.standard.data(forKey: key),
           let arr = try? JSONDecoder().decode([ProofClaim].self, from: d) { claims = arr }
    }
    private func save() {
        if let d = try? JSONEncoder().encode(claims) { UserDefaults.standard.set(d, forKey: key) }
    }
}
