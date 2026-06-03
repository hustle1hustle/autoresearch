# Hack 6 — Notarize-in-Animation. Implementation Notes

**Что делает.** Запускает notarize (GraphQL + selective disclosure proof) **во время** iOS app-switch return animation. iOS тратит ~400 мс на анимацию возврата от Safari/GitHub-app. В это окно мы кидаем GraphQL + proof. Юзер perceives "тап → done" без отдельного спиннера.

**Источник.** Архитектурно enable'нo Hack 1 (pre-warmed WebSocket) + Plaid's "callback ordering is not guaranteed" pattern ([Plaid Link docs](https://plaid.com/docs/link/ios/)). См. `../../mobile-ux-deep-research.md` §1 Hack 6.

**Где живёт.** Host-shell. Specifically в OAuth callback handler — момент сразу после ASWebAuthSession completion.

## Pre-requisites

- **Hack 1 уже работает.** WebSocket к verifier уже открыт, PKCE готов, roots loaded. Без Hack 1 нечего "прятать".
- TLSN build expose'ит async notarize API. См. `../../open-questions.md` Q2.

## iOS implementation

### Step 1. ASWebAuthSession completion handler fires notarize СРАЗУ

```swift
func startGitHubOAuth() async throws {
    // ASWebAuthSession показывает iOS sheet → GitHub OAuth → callback URL
    let result = try await webAuth.authenticate(
        url: githubAuthURL,
        callbackURLScheme: nil  // Universal Link
    )

    // ВАЖНО. фиктивный пере-render UI с .scaleEffect animation
    // запускается ОДНОВРЕМЕННО с notarize background work

    await withTaskGroup(of: Void.self) { group in
        // Background. оба работают параллельно
        group.addTask {
            await self.animateReturn()  // ~400ms iOS native animation
        }
        group.addTask {
            await self.exchangeAndNotarize(authResult: result)
        }
    }
}

@MainActor
func animateReturn() async {
    withAnimation(.snappy(duration: 0.4)) {
        viewState = .returning
    }
    try? await Task.sleep(nanoseconds: 400_000_000)
    withAnimation(.snappy(duration: 0.2)) {
        viewState = .notarizing  // если ещё не готов
    }
}

func exchangeAndNotarize(authResult: ASWebAuthenticationResult) async {
    do {
        let code = extractCode(from: authResult.callbackURL)
        let accessToken = try await GitHubOAuth.exchangeCode(
            code: code,
            codeVerifier: prover.pkce.verifier
        )
        // прямо в Hack 1 уже открытую сессию
        let proof = try await prover.notarize(
            target: .github,
            accessToken: accessToken
        )
        await showSuccess(proof)
    } catch {
        await showError(error)
    }
}
```

### Step 2. Visual transition matches notarize duration

Если notarize ~1-2 секунды, и iOS animation ~400 мс — есть ~600-1600 мс где UI нуждается в visual continuity.

Подход. multi-stage animation которая выглядит как natural "we're getting ready":

```swift
enum ViewState {
    case oauthInFlight   // OAuth runs
    case returning       // post-OAuth, animation in
    case notarizing      // notarize in flight (if слишком долго)
    case success(Proof)
}

struct ConnectGitHubView: View {
    @State private var state: ViewState = .oauthInFlight

    var body: some View {
        ZStack {
            switch state {
            case .oauthInFlight:
                EmptyView()  // ASWebAuthSession draws over us
            case .returning:
                // Animated logo / brand transition
                Image("rep-logo")
                    .scaleEffect(state == .returning ? 1.0 : 0.8)
                    .opacity(state == .returning ? 1.0 : 0.0)
            case .notarizing:
                // Stage progress (если не успели в animation окно)
                VStack(spacing: 12) {
                    Stage(label: "Connecting to GitHub", isDone: true)
                    Stage(label: "Confirming with notary", isActive: true)
                    Stage(label: "Sealing your proof", isDone: false)
                }
            case .success(let proof):
                SuccessView(proof: proof)
            }
        }
        .animation(.snappy, value: state)
    }
}
```

### Step 3. Если notarize FASTER чем animation

Best case. notarize done в 400-800 мс на residential. Animation ещё идёт.

```swift
if proof готов до animation done {
    // delay показа success до окончания animation
    try? await Task.sleep(...)  
    state = .success(proof)
}
```

Не show success mid-animation. Это глючно.

### Step 4. Если notarize SLOWER чем animation

If proof занимает > 1 секунду и animation done — переключиться на explicit stages:

```swift
// animation done at 400ms
if notarize не закончен {
    state = .notarizing  // show stages
}
// proof готов at 1500ms
state = .success(proof)
```

Stages должны быть честными. показывать **что именно** идёт (GraphQL fire, response received, proof computed), не generic spinner.

## Android implementation

Same logic. Активити-transition animation длится ~300-500 мс на Android. Используй `ViewModel.viewModelScope.launch` для parallel notarize.

```kotlin
class ConnectGitHubViewModel : ViewModel() {
    val state = MutableStateFlow<ViewState>(ViewState.OAuthInFlight)

    fun onOAuthReturned(callbackUri: Uri) {
        viewModelScope.launch {
            // Параллельно. animation + notarize
            launch { animateReturn() }
            launch { exchangeAndNotarize(callbackUri) }
        }
    }
}
```

## Что НЕ делать

- **Не показывай generic "Loading…" сразу после OAuth return.** Это нарушает anti-pattern "Spinner without context". Если notarize tonigh > animation окно — переключайся на named stages.
- **Не блокируй UI на notarize.** UI должен animation'ить, не блокировать.
- **Не пытайся скрыть медленный notarize.** Если real time > 2 секунды — лучше честно показать "Sealing your proof…" чем выглядеть как stuck.
- **Не используй `Task { ... }` без `@MainActor` для UI updates.** Animation states must be on MainActor.

## Совместимость

- **Hack 1** prerequisite. Pre-warm означает что WebSocket уже открыт когда мы fire notarize → minimum delay
- **Hack 2** stack'ится отлично. На repeat. Face ID ~500 мс анимация + parallel refresh + notarize → all hidden
- **Hack 4** prerequisite. Universal Link auto-return — без него мы не controle timing entry в host-shell
- **Hack 3, 5** ортогонально

## Edge cases

### Network drops mid-notarize

Если WebSocket падает во время animation — пользователь видит... что? Если ты прячешь в animation, и notarize fail'ит — animation done и юзер видит inactive screen без feedback.

Solution. timeout. После 2 секунд если notarize не done — переключиться на `.notarizing` state с stages.

```swift
let proofTask = Task { try await prover.notarize(...) }
let timeoutTask = Task {
    try await Task.sleep(nanoseconds: 2_000_000_000)
    if state == .returning { state = .notarizing }  // показать stages
}

let proof = try await proofTask.value
timeoutTask.cancel()
state = .success(proof)
```

### iOS animation skipped (low motion settings)

Юзер может выключить animations в Accessibility settings. Тогда animation runs 0 мс. Hack 6 effectively reverts на explicit stages. Document this.
