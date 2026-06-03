# Hack 3 — Pre-sheet Explainer. Implementation Notes

**Что делает.** Перед `ASWebAuthenticationSession` показывает один экран с объяснением. "Сейчас iOS спросит можно ли использовать github.com для входа. Пароль остаётся у GitHub." Когда iOS sheet появляется, юзер его ждёт, не пугается.

**Источник.** [Okta history of mobile SSO](https://developer.okta.com/blog/2022/01/13/mobile-sso) + [Plaid Best Practices](https://medium.com/@FintegrationFS/plaid-link-best-practices-ux-conversion-tips-that-reduce-drop-off-in-bank-linking-c3b5fddf8930). См. `../../mobile-ux-deep-research.md` §1 Hack 3.

**Где живёт.** Host-shell, между "Connect GitHub" tap и `ASWebAuthSession.start()` call.

## iOS implementation

### SwiftUI version

```swift
struct ConnectGitHubView: View {
    @State private var showPreSheet = false
    @AppStorage("hasSeenGitHubPreSheet") private var hasSeenPreSheet = false

    var body: some View {
        VStack {
            // Main connect button
            Button("Connect GitHub") {
                if !hasSeenPreSheet {
                    showPreSheet = true
                } else {
                    fireOAuth()
                }
            }
        }
        .sheet(isPresented: $showPreSheet) {
            PreSheetExplainer(
                platform: "GitHub",
                onContinue: {
                    hasSeenPreSheet = true
                    showPreSheet = false
                    fireOAuth()
                }
            )
        }
    }
}

struct PreSheetExplainer: View {
    let platform: String
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Connect \(platform)")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                Label("We'll ask \(platform) to share your username and contribution count",
                      systemImage: "checkmark.circle")
                Label("Next, iOS will ask permission to use \(platform.lowercased()).com to sign in",
                      systemImage: "info.circle")
                Label("Your password never leaves \(platform). We only see what they say, signed.",
                      systemImage: "lock")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding()

            Button("Continue with \(platform)") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .presentationDetents([.medium])
    }
}
```

### Persistence. показывать только первый раз

`@AppStorage("hasSeenGitHubPreSheet")` хранит флаг в UserDefaults. После первого Continue → флаг = true → pre-sheet никогда не показывается снова.

**Per-platform флаги.** `hasSeenGitHubPreSheet`, `hasSeenStravaPreSheet`, etc. Не один глобальный — каждый платформа первый раз достоин объяснения.

## Android implementation

На Android Chrome Custom Tabs тихо шарит cookie jar без consent sheet ([Steamclock CCT writeup](https://steamclock.com/blog/2025/05/android-chrome-custom-tabs/)). **Hack 3 на Android опционален**, потому что нет scary sheet'а который надо предупредить.

**ОДНАКО** Hack 3 на Android полезен если ты используешь WebView (не CCT) или хочешь показать "what we're going to share" контекст. Но конверсия impact минимален.

```kotlin
class ConnectGitHubFragment : Fragment() {
    private val prefs by lazy { requireContext().getSharedPreferences("rep.prefs", MODE_PRIVATE) }

    private fun onConnectClick() {
        val seenPreSheet = prefs.getBoolean("hasSeenGitHubPreSheet", false)

        if (!seenPreSheet) {
            showPreSheetDialog {
                prefs.edit().putBoolean("hasSeenGitHubPreSheet", true).apply()
                launchCustomTabs()
            }
        } else {
            launchCustomTabs()
        }
    }
}
```

Pre-sheet на Android — bottom sheet с тем же контентом что iOS. Material Motion для появления.

## Copy. что писать

**Структура.** Три блока. (1) что произойдёт сейчас, (2) что мы спросим у платформы, (3) гарантия что пароль не покинет платформу.

**GitHub-specific.**
```
Connect GitHub

  ✓ We'll ask GitHub to share your username and contribution count
  ℹ Next, iOS will ask permission to use github.com to sign in
  🔒 Your password never leaves GitHub. We only see what they say, signed.

  [Continue with GitHub]
```

**Strava-specific.**
```
Connect Strava

  ✓ We'll ask Strava to share your activities and stats
  ℹ Strava app will open for you to approve  (если deep-link)
       или
  ℹ Next, iOS will ask permission to use strava.com to sign in  (если ASWebAuth)
  🔒 Your password never leaves Strava. We only see what they say, signed.

  [Continue with Strava]
```

**Duolingo-specific (cookie path).**
```
Connect Duolingo

  ✓ We'll read your streak and XP from your Duolingo session
  ℹ Next, iOS will ask permission to use duolingo.com to sign in
  🔒 Your session stays on your device. We only see what we need.

  [Continue with Duolingo]
```

### NOT to say

- ❌ "Tap Continue to continue" — generic, doesn't add info
- ❌ "We respect your privacy" — empty promise without specifics
- ❌ "This is secure" — adjective without proof
- ❌ "Loading…" — это pre-sheet, не loading screen

## Что НЕ делать

- **Не показывай pre-sheet каждый раз.** Только first time per platform. После того как юзер тапнул Continue хоть один раз — sheet не появляется.
- **Не делай pre-sheet модальный с no-skip.** Юзер должен иметь Cancel button рядом с Continue. Если нет — это hostage UX.
- **Не делай pre-sheet длиннее 3 bullet points.** Если ты пишешь подробный legal text — это не pre-sheet, это privacy policy. Pre-sheet быстро объясняет immediate consequence.
- **Не сочетай pre-sheet с onboarding.** Pre-sheet ≠ welcome screen. Pre-sheet появляется на edge of action, не в начале flow.

## Совместимость

- **Hack 1** ортогонален. Pre-warm WebSocket идёт фоном пока юзер читает pre-sheet. Хорошее timing
- **Hack 4** prerequisite. Universal Link return должен работать к моменту когда юзер вернётся
- **Hack 6** ортогонален. Pre-sheet перед OAuth, notarize-in-animation после
