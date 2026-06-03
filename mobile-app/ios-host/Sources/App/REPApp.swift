import SwiftUI

@main
struct REPApp: App {
    @StateObject private var router = AppRouter()
    @StateObject private var graph = ContextGraph()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .environmentObject(graph)
                // Hack 4: OAuth callback returns as a Universal Link.
                .onOpenURL { UniversalLinkRouter.shared.handle($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { UniversalLinkRouter.shared.handle(url) }
                }
        }
    }
}

@MainActor
final class AppRouter: ObservableObject {
    enum Screen: Equatable { case context, connect, success(ProofClaim) }
    @Published var screen: Screen = .context
}

struct RootView: View {
    @EnvironmentObject var router: AppRouter

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch router.screen {
            case .context:           ContextView()
            case .connect:           ConnectGitHubView()
            case .success(let claim): ProofSuccessView(claim: claim)
            }
        }
        .animation(Theme.snappy, value: router.screen)   // Hack 6: snappy transitions
    }
}
