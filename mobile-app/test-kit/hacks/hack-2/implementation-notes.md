# Hack 2 — Refresh Token + Face ID. Implementation Notes

**Что делает.** После первого proof'а сохраняем OAuth refresh_token в Keychain под `.biometryCurrentSet`. На повторе — Face ID → silent refresh-grant → notarize. Без app-switch'а и OAuth дансом.

**Источник.** GitHub OAuth refresh tokens (8 ч access, 6 мес refresh per [GitHub docs](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/refreshing-user-access-tokens)) + Apple `SecAccessControl` recommended pattern. См. `../../mobile-ux-deep-research.md` §1 Hack 2.

**Где живёт.** Host-shell. После первого успешного OAuth с GitHub, host-shell сохраняет refresh_token, и для повторов использует его вместо нового OAuth дансом.

## Pre-requisites

- Hack 4 (Universal Link auto-return) уже работает, иначе первый proof неполноценен
- Refresh token поддерживается GitHub OAuth app'ом (включается в OAuth App settings)
- iOS 17+ для нормального `LAContext.localizedReason` customization

## iOS implementation

### Сохранение refresh_token

```swift
import Security
import LocalAuthentication

func saveRefreshToken(_ token: String, platform: String) throws {
    let access = SecAccessControlCreateWithFlags(
        nil,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        .biometryCurrentSet,
        nil
    )!

    let attrs: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.rep.\(platform).refresh",
        kSecAttrAccount as String: "user",
        kSecValueData as String: token.data(using: .utf8)!,
        kSecAttrAccessControl as String: access,
    ]

    SecItemDelete([
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.rep.\(platform).refresh"
    ] as CFDictionary)

    let status = SecItemAdd(attrs as CFDictionary, nil)
    guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
}
```

### Чтение с Face ID

```swift
func readRefreshToken(platform: String) async throws -> String {
    let context = LAContext()
    context.localizedReason = "Use Face ID to refresh \(platform.capitalized) access"

    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.rep.\(platform).refresh",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
        kSecUseAuthenticationContext as String: context,
    ]

    var data: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &data)

    guard status == errSecSuccess, let tokenData = data as? Data,
          let token = String(data: tokenData, encoding: .utf8) else {
        throw KeychainError.notFound
    }
    return token
}
```

### Использование в re-prove flow

```swift
func reproveGitHub() async throws {
    do {
        let refreshToken = try await readRefreshToken(platform: "github")
        let accessToken = try await GitHubOAuth.refresh(refreshToken: refreshToken)
        let proof = try await TLSNProver.notarizeGitHub(accessToken: accessToken)
        await showSuccess(proof)
    } catch KeychainError.notFound {
        // Refresh token revoked or expired — fall back to full OAuth
        try await fullOAuthGitHub()
    } catch is LAError {
        // Face ID failed / cancelled — user explicit cancel
        await showFaceIDCancel()
    }
}
```

## Android implementation

### Сохранение

```kotlin
val masterKey = MasterKey.Builder(context)
    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
    .setUserAuthenticationRequired(true, 0)  // require biometric on every access
    .build()

val sharedPrefs = EncryptedSharedPreferences.create(
    context, "rep.refresh", masterKey,
    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
)
sharedPrefs.edit().putString("github.refresh", refreshToken).apply()
```

### Чтение с BiometricPrompt

```kotlin
val biometricPrompt = BiometricPrompt(activity, executor,
    object : BiometricPrompt.AuthenticationCallback() {
        override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
            val token = sharedPrefs.getString("github.refresh", null)
            lifecycleScope.launch { reproveWithToken(token) }
        }
    })

val promptInfo = BiometricPrompt.PromptInfo.Builder()
    .setTitle("Refresh GitHub access")
    .setSubtitle("Use biometric to mint your proof again")
    .setAllowedAuthenticators(BIOMETRIC_STRONG)
    .build()

biometricPrompt.authenticate(promptInfo)
```

## Edge cases

### Re-enrollment Face ID

Если юзер добавил новый Face ID — `.biometryCurrentSet` инвалидирует Keychain item. **Это feature, не bug.** Host-shell на failed read должен fall back на full OAuth. Юзер пере-аутентифицируется один раз, потом снова Face ID работает.

### Refresh token revoked

Юзер мог пойти в GitHub Settings → Applications → REP и отозвать. На refresh GitHub отдаст 400 / 401. Host-shell должен поймать, удалить Keychain entry, fall back на full OAuth.

### App reinstall

Keychain item с `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` НЕ выживает app uninstall+reinstall (на iOS depends на iCloud Keychain settings). На Android `EncryptedSharedPreferences` тоже не выживает. Это OK. fall back на full OAuth.

### Token rotation

GitHub отдаёт новый refresh token при каждом use (rotation). Host-shell ОБЯЗАН обновить Keychain entry новым refresh token каждый раз, иначе следующий refresh failед.

```swift
let response = try await GitHubOAuth.refresh(refreshToken: oldRefresh)
try saveRefreshToken(response.refresh_token, platform: "github")  // overwrite old
return response.access_token
```

## Что НЕ делать

- **Не используй `.biometryAny` вместо `.biometryCurrentSet`** — это разрешает любой добавленный Face ID (security hole для shared devices)
- **Не сохраняй access_token в Keychain** — он живёт 8 часов, smysl'а нет
- **Не используй `kSecAttrAccessibleAlways`** или `…AlwaysThisDeviceOnly` — это разрешает access без unlock'а
- **Не показывай Face ID prompt без визуального context'а в host-shell'е** — юзер должен видеть в host-shell "Refreshing GitHub access" пока iOS prompt висит, иначе scary

## Совместимость с другими хаками

- **Hack 1** ортогонален. pre-warm WebSocket работает параллельно с refresh-grant
- **Hack 6** stack'ится. Face ID анимация занимает ~500-800 мс, в которые можно спрятать notarize если он быстрый
- **Hack 4** prerequisite. Universal Link нужен для первого proof'а который сохраняет refresh token
