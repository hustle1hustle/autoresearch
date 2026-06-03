# Hack 5 — Conditional UI Passkey Probe. Implementation Notes

**Что делает.** Запускает `mediation: "conditional"` WebAuthn assertion в фоне. Если у юзера есть passkey для RP — iOS surface'ит в системной autofill chip. **Если нет — НИЧЕГО не происходит**, ни UI, ни friction. RP (мы) не узнаём что юзер пробовал.

**Источник.** Apple WWDC22 conditional mediation talk + [Corbado iOS 18 passkeys](https://www.corbado.com/blog/ios-18-passkeys-automatic-passkey-upgrades). См. `../../mobile-ux-deep-research.md` §1 Hack 5.

**Где применим.**
- ✅ **REP-self login** — если юзер уже set up passkey в REP на этом девайсе
- ✅ **Cookie-path targets** — Duolingo / LeetCode когда они выкатят passkey support (или для login.duolingo.com если они уже поддерживают)
- ❌ **GitHub OAuth** — GitHub принимает passkey для github.com sign-in, но **не для OAuth app token issuance**. Так что прямой OAuth путь не помогает

## Pre-requisites

- iOS 17.5+ для `ASAuthorizationPlatformPublicKeyCredentialProvider` + `requestStyle: .conditional`
- Android 14+ для `CredentialManager.getCredential` с `isConditional=true`
- AASA включает `webcredentials:rep.xyz` (отдельно от `applinks:` для passkey scope)

## iOS implementation

### Step 1. AASA для webcredentials

```json
{
  "applinks": { ... },
  "webcredentials": {
    "apps": ["TEAMID.com.rep.app"]
  }
}
```

И entitlement `com.apple.developer.associated-domains` уже включает `applinks:rep.xyz` — для webcredentials ничего отдельно не нужно, тот же entitlement покрывает.

### Step 2. Fire conditional probe

```swift
import AuthenticationServices

class PasskeyProbe: NSObject, ObservableObject, ASAuthorizationControllerDelegate {
    @Published var passkeyAvailable: Bool? = nil  // nil = unknown, true/false = probed

    func startConditionalProbe(challenge: Data) {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: "rep.xyz"
        )
        let request = provider.createCredentialAssertionRequest(challenge: challenge)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self

        // ВАЖНО. performAutoFillAssistedRequests, не performRequests
        controller.performAutoFillAssistedRequests()
    }

    func authorizationController(_ controller: ASAuthorizationController,
                                  didCompleteWithAuthorization authorization: ASAuthorization) {
        // Юзер выбрал passkey из autofill chip
        if let cred = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            handlePasskeyAssertion(cred)
        }
    }

    func authorizationController(_ controller: ASAuthorizationController,
                                  didCompleteWithError error: Error) {
        // Конкретно для conditional UI — error означает не "сломалось", а "юзер выбрал другой login"
        // или "passkey не доступен silently". Не блокируем UI.
    }
}
```

### Step 3. Wire в SwiftUI

```swift
struct LoginView: View {
    @StateObject private var probe = PasskeyProbe()

    var body: some View {
        VStack {
            TextField("Email", text: $email)
                .textContentType(.username)  // ← КРИТИЧНО для conditional UI

            SecureField("Password", text: $password)
                .textContentType(.password)

            Button("Sign in with Passkey", action: {
                // Manual fallback (если юзер хочет explicit, не через autofill)
                probe.startExplicitRequest()
            })
        }
        .onAppear {
            probe.startConditionalProbe(challenge: generateChallenge())
        }
    }
}
```

`.textContentType(.username)` сигналит iOS что эта форма принимает username. iOS показывает passkey suggestion если usernameField focused.

## Android implementation

```kotlin
class LoginViewModel : ViewModel() {
    private val credentialManager = CredentialManager.create(context)

    fun startConditionalProbe() {
        viewModelScope.launch {
            try {
                val request = GetCredentialRequest.Builder()
                    .addCredentialOption(
                        GetPublicKeyCredentialOption(
                            requestJson = challengeJson,
                            isConditional = true  // ← critical
                        )
                    )
                    .build()

                val response = credentialManager.getCredential(
                    context = activity,
                    request = request
                )

                // Юзер выбрал passkey
                handlePasskey(response.credential)
            } catch (e: GetCredentialException) {
                // Conditional UI silent failure — fine
            }
        }
    }
}
```

## Где Hack 5 показывается юзеру

- **iOS.** System autofill chip над клавиатурой когда юзер touch'ит email/password field. Если есть passkey — chip показывает "Sign in with Face ID".
- **Android 14+.** Suggestion bar над клавиатурой.
- **Не показывается.** Если passkey нет, либо если юзер не открыл клавиатуру.

## Edge cases

### Passkey есть, но iCloud Keychain выключен

iCloud Keychain держит passkeys synced. Если выключен — passkey доступен только на устройстве где создан. Hack 5 покажет passkey на устройстве создания, не покажет на других устройствах юзера.

### Server-side challenge

Conditional UI требует server-issued challenge. Реализуй endpoint `/api/passkey/challenge` который выдаёт random bytes. Сохрани challenge server-side для validation.

### Discovery vs proactive

`mediation: "conditional"` НЕ запрашивает discoverable credentials списком. iOS сам решает что surface'ить в autofill. RP не learn'ит availability.

Если ты хочешь explicit fallback "Sign in with Passkey" button — это `performRequests()`, не `performAutoFillAssistedRequests()`. Эта вариант проактивный.

## Что НЕ делать

- **Не используй `performRequests()` для probe.** Это покажет полный modal которые ломает silent-probe principle
- **Не сохраняй passkey availability state.** Conditional UI privacy-preserving by design. Если ты сохранил "user has passkey" в state — ты нарушил W3C principle
- **Не вызывай conditional UI на launch screen.** Делай только когда юзер на login screen с email/password fields focused

## Совместимость

- **Hack 1-4, 6** все ортогональны. Hack 5 это отдельный путь входа который собирает entire auth flow в 1 тап если applicable.

## Limitations

- **GitHub OAuth НЕ принимает WebAuthn для token issuance.** Hack 5 не помогает для GitHub direct flow. Работает для github.com sign-in (cookie path).
- **REP-self login** — где Hack 5 однозначно помогает. Если юзер залогинен в REP через passkey, мы знаем его REP identity не запрашивая email.

## Real impact в нашем контексте

В Tier-1 targets Hack 5 применим:
- **GitHub.** ❌ direct OAuth не принимает
- **Strava.** ❌ direct OAuth не принимает
- **Duolingo.** ⚠️ depends что у них на login. Если passkey support — works для cookie path
- **LeetCode.** ⚠️ same
- **REP-self login.** ✅ полностью применим

Положительный вывод. Hack 5 не для proof'ов специфически, а для **сокращения REP-self login flow** до 1 тапа. Это improvement для onboarding общего, не для GitHub hero специфически.
