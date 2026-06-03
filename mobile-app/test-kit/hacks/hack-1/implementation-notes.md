# Hack 1 — Pre-warm WebSocket. Implementation Notes

**Что делает.** Открыть WebSocket к verifier'у и сгенерировать PKCE challenge **до того** как юзер тапнул "Connect GitHub". К моменту тапа сеть-часть уже оплачена.

**Источник идеи.** Plaid Link iOS docs — `Plaid.create()` preload + onLoad callback (см. `../mobile-ux-deep-research.md` §1 Hack 1, [Plaid iOS docs](https://plaid.com/docs/link/ios/)).

**Где живёт.** Host-shell wrapper вокруг TLSN build. **НЕ модификация самого TLSN.** Pre-warm — это life-cycle hook в host-shell'е, который опережает blocking call в TLSN library.

## Pre-requisites

- Open Question Q2 в `../open-questions.md` должен быть RESOLVED. Если TLSN build не expose'ит separate `Prover.connect()` API (только blocking `Prover.notarize()`), Hack 1 неимплементируем без forking'а
- Доступ к Mozilla root certs / WebPKI roots в host-shell'е

## iOS implementation

### SwiftUI approach

```swift
// в твоём connect-screen view:
struct ConnectGitHubView: View {
    @State private var proverReady: Bool = false
    @StateObject private var prover = ProverPreWarm.shared

    var body: some View {
        VStack {
            Text("Connect GitHub")
            Button("Continue with GitHub") {
                // К этому моменту prover.session уже открыт
                fireOAuth()
            }
        }
        .task {
            // Запускается при появлении view, до любого таптания
            await prover.connect(
                verifier: URL(string: "wss://verifier.rep.xyz/notary")!,
                roots: .mozillaWebPKI
            )
            proverReady = true
        }
    }
}

class ProverPreWarm: ObservableObject {
    static let shared = ProverPreWarm()
    var session: TLSNProverSession?
    var pkce: PKCE?

    func connect(verifier: URL, roots: RootCertStore) async {
        do {
            self.session = try await TLSNProverSession.open(verifier: verifier, roots: roots)
            self.pkce = PKCE.generate()
        } catch {
            // не блокируем UI, просто логируем — на тап мы fallback'нем на cold start
            os_log("Pre-warm failed: %@", error.localizedDescription)
        }
    }
}
```

### Что измеряется

Добавь measurement:
```swift
let t0 = CFAbsoluteTimeGetCurrent()
await prover.connect(...)
let t1 = CFAbsoluteTimeGetCurrent()
analytics.emit(.notarize_websocketConnected, properties: [
    "duration_ms": (t1 - t0) * 1000,
    "stage": "prewarm"
])
```

### Edge case. flaky network

Pre-warm BEST EFFORT. Не блокируй CTA на pre-warm success. Если pre-warm провалился — host-shell делает обычный `connect()` на тапе. Just slower, not broken.

```swift
Button("Continue with GitHub") {
    Task {
        if prover.session == nil {
            // Pre-warm failed. Fallback to on-demand
            await prover.connect(...)
        }
        fireOAuth()
    }
}
```

### Edge case. background / kill

iOS может убить session в background. Pre-warm не выживает app re-launch. На launch screen — re-prewarm. На return from background — re-prewarm если session.state != active.

```swift
.onChange(of: scenePhase) { phase in
    if phase == .active && prover.session?.isActive != true {
        Task { await prover.connect(...) }
    }
}
```

## Android implementation

### Kotlin approach

```kotlin
class ConnectGitHubViewModel : ViewModel() {
    private val _proverReady = MutableStateFlow(false)
    val proverReady = _proverReady.asStateFlow()

    private var session: TLSNProverSession? = null

    init {
        viewModelScope.launch {
            try {
                session = TLSNProverSession.open(
                    verifier = "wss://verifier.rep.xyz/notary",
                    roots = WebPKIRoots.mozilla()
                )
                _proverReady.value = true
            } catch (e: Exception) {
                Log.w("Hack1", "Pre-warm failed", e)
                // не блокируем UI
            }
        }
    }
}
```

### Что измеряется (Android)

```kotlin
val t0 = SystemClock.elapsedRealtime()
session = TLSNProverSession.open(...)
val t1 = SystemClock.elapsedRealtime()
analytics.emit("notarize_websocketConnected", mapOf(
    "duration_ms" to t1 - t0,
    "stage" to "prewarm"
))
```

## Что НЕ делать

- **Не блокируй UI на pre-warm.** Connect-screen должен быть полностью функционален даже если pre-warm идёт в фоне или провалился.
- **Не делай pre-warm на app launch screen.** Это слишком рано — юзер может не пойти на connect flow. Делай pre-warm на entry в connect-flow screen.
- **Не используй WKWebView для pre-warm.** Hack 1 это сетевой pre-warm, не UI pre-warm.
- **Не модифицируй TLSN build чтобы добавить hooks.** Если build не expose'ит separate `.connect()` API, отметь в `open-questions.md` и оставь Hack 1 как "not implementable on current build".

## Совместимость с другими хаками

- **Hack 6 (notarize-in-animation)** ЗАВИСИТ от Hack 1. Без pre-warm нечего скрывать в animation.
- **Hack 4 (Universal Link)** ОРТОГОНАЛЕН. Hack 4 про возврат, Hack 1 про подготовку. Сочетаемы.

## Расположение в host-shell architecture

```
HostShellApp
├── EntryView
│   └── ConnectGitHubView          ← pre-warm запускается ЗДЕСЬ (.task)
│       ├── prover (Hack 1 instance)
│       └── ASWebAuthSession trigger
└── ProofSuccessView
```

Pre-warm should happen NOT on app launch but on entering the "I want to connect this platform" screen. Иначе ты warm'нешь WebSocket на юзеров которые никогда не дойдут до notarize.
