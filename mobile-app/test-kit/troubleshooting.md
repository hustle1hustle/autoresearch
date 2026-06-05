# Troubleshooting — common failures + fixes

Search by error message или symptom. Consolidated из всех hack/target/setup файлов в один searchable place.

## Index

- [Build / Xcode issues](#build--xcode-issues)
- [TLSNotary prover issues](#tlsnotary-prover-issues)
- [OAuth flow issues](#oauth-flow-issues)
- [Universal Link / AASA issues](#universal-link--aasa-issues)
- [Keychain / Face ID issues](#keychain--face-id-issues)
- [Notary / verifier issues](#notary--verifier-issues)
- [Cookie-path target issues](#cookie-path-target-issues)
- [Network / TLS issues](#network--tls-issues)
- [Measurement / instrumentation issues](#measurement--instrumentation-issues)

---

## Build / Xcode issues

### "module 'TlsnProverFFI' not found"

**Cause.** Modulemap missing or wrong path в xcframework.

**Fix.**
1. Regenerate UniFFI bindings (`cargo run --bin uniffi-bindgen generate src/lib.udl --language swift --out-dir ./generated`)
2. Verify modulemap exists. `find TlsnProver.xcframework -name "module.modulemap"`
3. Re-pack xcframework (см. [setup/01-xcframework-build.md](setup/01-xcframework-build.md))

### "Undefined symbol: _tlsn_prover_<func>"

**Cause.** Static library не linked, или wrong arch.

**Fix.**
1. В Xcode. Build Settings → Other Linker Flags → add `-ObjC`
2. Verify xcframework added to "Frameworks, Libraries, and Embedded Content" с Embed & Sign
3. Check arch matches device. M-series Mac simulator needs `aarch64-apple-ios-sim`, not x86_64

### "Code signing error: associated-domains entitlement is missing"

**Cause.** Free Apple ID не supports Associated Domains. Or entitlement file not updated for Release.

**Fix.**
1. Upgrade to paid Apple Developer account ($99/yr), OR
2. Use direct Xcode install (not TestFlight) for personal device development
3. Verify both `Entitlements-Debug.plist` AND `Entitlements-Release.plist` have `applinks:r3p.xyz`

### "Untrusted Developer" блокирует app на iPhone

**Cause.** Free Apple ID developer profile not trusted.

**Fix.** На iPhone. Settings → General → VPN & Device Management → tap developer profile → Trust.

### Build занимает 10+ минут

**Cause.** Rust release builds heavy, especially for iOS multi-arch.

**Fix.** Normal first time. Subsequent builds incremental (~30 секунд). Use Rust `sccache` if want even faster: `cargo install sccache && export RUSTC_WRAPPER=sccache`.

### "Target architecture mismatch"

**Cause.** Building for wrong simulator arch on M-series Mac.

**Fix.** Build Settings → "Excluded Architectures" → DEBUG → Any iOS Simulator SDK → ensure `arm64` not excluded.

---

## TLSNotary prover issues

### "Mode 'Proxy' not supported by build"

**Cause.** Build was compiled without proxy mode feature flag.

**Fix.** Rebuild с proxy enabled. In `Cargo.toml` of `tlsn-mobile`:
```toml
[features]
default = ["proxy"]
```
Then re-run [setup/01-xcframework-build.md](setup/01-xcframework-build.md).

### "Notarize timeout" / hangs

**Cause.** One of:
- Notary unreachable from device
- Notary URL wrong scheme (`http://` vs `wss://`)
- Domain not whitelisted в notary config

**Fix.**
1. `docker logs rep-notary` → check if connection received
2. Verify `verifierURL` в Swift code (`wss://`, not `ws://` or `https://`)
3. Add target host to `prover.proxy.allowed_domains` в notary config.yaml, restart

### "max_recv_data exceeded"

**Cause.** Response from target server больше чем prover ожидает.

**Fix.** Bump в `MpcTlsConfig` (или wherever `max_recv_data` is set):
```rust
let config = MpcTlsConfig::builder()
    .max_sent_data(8 * 1024)         // 8 KB
    .max_recv_data(64 * 1024)        // 64 KB для multi-endpoint kitchen-sink
    .build()?;
```

### "Selective reveal range out of bounds"

**Cause.** Byte range calculation wrong (auth header position mismatch).

**Fix.** Don't hardcode byte ranges. Build request, capture bytes, search for the `Authorization` header value within those bytes, compute reveal/redact ranges programmatically.

```swift
let sent = prover.transcript().sent()
let needle = "Bearer \(token)".data(using: .utf8)!
guard let position = sent.range(of: needle) else { fatalError("auth header not found") }
// reveal 0..position.lowerBound, then position.upperBound..sent.count
```

---

## OAuth flow issues

### "redirect_uri_mismatch"

**Cause.** Callback URL in OAuth request doesn't exactly match registered URL.

**Fix.** Check trailing slashes, http vs https, exact case. Re-verify OAuth app settings → Authorization callback URL.

### "incorrect_client_credentials" (GitHub)

**Cause.** Client Secret mistyped или extra whitespace.

**Fix.** Regenerate Client Secret in GitHub OAuth App settings. Copy carefully (no leading/trailing space).

### Refresh token не возвращается (GitHub)

**Cause.** Using OAuth App вместо GitHub App. OAuth Apps don't issue refresh tokens.

**Fix.** Recreate as GitHub App (см. [setup/02-oauth-apps.md § A](setup/02-oauth-apps.md#a-github-oauth-app-hero)).

### OAuth state mismatch на callback

**Cause.** State value lost между OAuth start и callback (app restarted, state в memory).

**Fix.** Persist state в Keychain or UserDefaults:
```swift
UserDefaults.standard.set(state, forKey: "oauth.github.state.pending")
// затем на callback:
let expected = UserDefaults.standard.string(forKey: "oauth.github.state.pending")
guard callbackState == expected else { throw OAuthError.stateMismatch }
```

### Strava "Connection Error" при app-switch deep-link

**Cause.** Strava native app sometimes fails to handle `strava://oauth/mobile/authorize` URL.

**Fix.** Fall back to web OAuth `https://www.strava.com/oauth/mobile/authorize?...`. Detect failure quickly:
```swift
if UIApplication.shared.canOpenURL(URL(string: "strava://")!) {
    UIApplication.shared.open(stravaDeepLink) { success in
        if !success { fallbackToWeb() }
    }
} else {
    fallbackToWeb()
}
```

### StackOverflow consent screen wants "key" but not provided

**Cause.** Stack Apps OAuth needs `&key=<app-key>` в каждом API request (post-token).

**Fix.** Add app key to every request URL OR header. Token alone insufficient.

---

## Universal Link / AASA issues

### Universal Link не маршрутизирует, остаётся в Safari

**Cause.** AASA не fetched or invalid.

**Diagnostic.**
1. `curl -i https://r3p.xyz/.well-known/apple-app-site-association` → 200 OK, Content-Type: application/json, no redirects
2. On device. Settings → Developer → Associated Domain Development → enable
3. `swcutil show` в Mac Terminal → look for `applinks:r3p.xyz` status (`Validated` or `Failed`)

**Fix.**
- Если file 404 → re-host
- Если wrong content-type → server config (см. [setup/04-universal-links.md § Server config](setup/04-universal-links.md))
- Если redirects → server config (no redirects allowed)
- Если AASA malformed → validate JSON (`jq` it)

### TestFlight AASA delay (до 15 минут)

**Cause.** Known iOS quirk via TestFlight install. AASA fetch может delay significantly.

**Fix.** Use fallback web page at callback URL with deep-link button. Wait 15+ минут после install. Verify через `swcutil show`.

### "Entitlement-Release.plist missing applinks"

**Cause.** Xcode capability UI updates только Debug entitlements file.

**Fix.** Open both files, ensure both have `com.apple.developer.associated-domains` array containing `applinks:r3p.xyz`.

### CDN cache stale (production AASA updated но iOS sees old version)

**Cause.** iOS 14+ uses Apple's CDN with TTL.

**Fix.**
1. Wait 24 hours (CDN TTL)
2. Or bump app version, re-install
3. Or use `?mode=developer` in entitlement (dev only)

---

## Keychain / Face ID issues

### Face ID prompt не появляется когда читаем refresh token

**Cause.** Keychain item saved without `.biometryCurrentSet` flag.

**Fix.** Re-save using correct flags:
```swift
let access = SecAccessControlCreateWithFlags(
    nil,
    kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    .biometryCurrentSet,
    nil
)!
let attrs: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.rep.github.refresh",
    kSecValueData as String: token.data(using: .utf8)!,
    kSecAttrAccessControl as String: access,
]
```

### Keychain item invalidated after Face ID re-enrollment

**Cause.** `.biometryCurrentSet` invalidates when user adds new Face ID. **This is a feature, not a bug.**

**Fix.** Detect via `errSecAuthFailed` or similar; clear Keychain entry; fall back to full OAuth re-auth. User does it once, then Face ID works again.

### "Code execution failed" with biometric Keychain access

**Cause.** App в background trying to read biometry-locked item.

**Fix.** Wrap read in foreground check:
```swift
guard UIApplication.shared.applicationState == .active else {
    throw KeychainError.notForegrounded
}
```

### `LAError.canceledByUser` exception

**Cause.** User tapped Cancel on Face ID prompt.

**Fix.** Не показывай error screen. Just return to entry. User explicit cancel ≠ error.

---

## Notary / verifier issues

### "Allowed domains check failed"

**Cause.** Target host (e.g. `api.github.com`) not в notary's `prover.proxy.allowed_domains` config.

**Fix.** Add domain to config, restart notary:
```yaml
prover:
  proxy:
    allowed_domains:
      - "api.github.com"
      - "api.strava.com"
      # ...
```

### "TLS handshake error" with self-signed notary cert

**Cause.** iOS doesn't trust dev cert.

**Fix.**
- Production. use Let's Encrypt cert (via Caddy or certbot)
- Dev. add cert to iOS Trust Store (Settings → General → About → Certificate Trust Settings → enable trust for your dev cert)

### "Connection refused" from iOS simulator to local notary

**Cause.** Simulator's `localhost` ≠ Mac's `localhost`.

**Fix.** Use `host.docker.internal` (if Docker) OR Mac's WiFi IP (`ipconfig getifaddr en0`) instead of `localhost`.

### "Out of memory" when MPC mode на large requests

**Cause.** MPC needs RAM ∝ (max_sent_data + max_recv_data) × garbled-circuit overhead.

**Fix.**
- Bump VPS RAM
- Lower `max_sent_data` / `max_recv_data` if fact is small
- Use proxy mode когда possible (no GC, much less RAM)

---

## Cookie-path target issues

### Cookie replay returns 401

**Cause.** Cookie IP- or UA-pinned. Server detects mismatch between session creation and replay.

**Fix.**
1. Try realistic User-Agent (matching iOS Safari):
   ```
   Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1
   ```
2. If still fails → switch to MPC mode (user device makes connection)
3. Document outcome в [`targets/<target>.md`](targets/) mode recommendation

### Cloudflare 403 / "Just a moment..." HTML page

**Cause.** CF challenge triggered on datacenter notary IP.

**Fix.**
- Switch to MPC mode for this target
- Capture `cf_clearance` cookie alongside session cookie (limited help)
- Document occurrence rate

### `csrftoken` rejected on POST

**Cause.** Server requires X-CSRFToken header matching cookie csrftoken value.

**Fix.** Replay both cookie AND header:
```swift
request.setValue("\(cookies)", forHTTPHeaderField: "Cookie")
request.setValue(csrfTokenValue, forHTTPHeaderField: "X-CSRFToken")  // or "x-csrftoken"
```

### Session cookie rotates on each authenticated request

**Cause.** Sliding rotation (some sites do this for security).

**Fix.**
- Saved cookies become invalid after first replay
- Hack 2 doesn't fully apply for these targets; modify flow to re-capture before each proof
- Document в `targets/<target>.md`

### `__cf_bm` cookie expired

**Cause.** Cloudflare bot-management cookie short-lived (30 min).

**Fix.** Don't try to persist CF cookies in Keychain. Capture fresh each time через ASWebAuthSession.

---

## Network / TLS issues

### "TLS version not supported"

**Cause.** TLSNotary historically pinned to TLS 1.2 + specific cipher suite. Target endpoint requires TLS 1.3.

**Fix.**
- Verify current prover TLS support (check `crates/notary-server` or `tlsn-mobile` source)
- If 1.2 only → some targets unsupported (need server-side TLS 1.2 fallback enabled)
- Long-term. wait for TLSN TLS 1.3 support

### "Certificate not trusted"

**Cause.** WebPKI root store outdated or missing CA.

**Fix.** Use Mozilla's WebPKI bundle:
```swift
let roots = TLSNRoots.mozillaWebPKI()  // или whatever wrapper exposes
```

### Notarize succeeds но response empty/garbled

**Cause.** Gzip encoding не handled by prover.

**Fix.** Force identity encoding:
```http
GET ... 
Accept-Encoding: identity
```

(`api.stackexchange.com` особенно requires this — см. [`targets/stackoverflow.md`](targets/stackoverflow.md).)

---

## Measurement / instrumentation issues

### Events not persisting

**Cause.** File write failure (permissions, full disk).

**Fix.**
- iOS. ensure file written to Documents directory (`FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]`)
- Android. ensure file written to internal storage (`context.filesDir`)
- Check disk space

### Stopwatch / timestamp drift

**Cause.** Using `Date()` для duration (subject to system clock changes).

**Fix.** Use monotonic clock:
- iOS. `CFAbsoluteTimeGetCurrent()` or `mach_absolute_time()` или `ProcessInfo.processInfo.systemUptime`
- Android. `SystemClock.elapsedRealtime()`

### "Perceived time" survey gives wildly varying numbers

**Cause.** Subjective measurement requires N≥30 for stat sig. N=10 insufficient.

**Fix.** Acknowledge limitation. Take median, document как direction-finding metric.

### Comparison CSV cells filled but inconsistent

**Cause.** Different testers using different methodologies.

**Fix.** Document methodology в notes column per row. Standardize on 10 attempts, median, fixed Wi-Fi/5G network type.

---

## Если ничего не помогает

1. **Check the date of test-kit docs.** Если research files старше 2-3 месяцев — TLSNotary API, GitHub OAuth, etc могли измениться. Re-check upstream docs.

2. **Search Apple Developer Forums** для iOS-specific issues.

3. **Open issue в TLSNotary repo** для prover-specific bugs.

4. **Open issue в this kit repo** для documentation gaps.

5. **Pair with another developer** на 30 минут screen-share. Часто свежий взгляд показывает obvious miss.

---

## Что обновлять после resolving

Когда ты решил issue которого нет в этом файле — **add it here** для следующего dev'а. Structure:

```markdown
### "Error message or symptom"

**Cause.** What was wrong

**Fix.** What you did

(Optional. when this happens / how to avoid)
```

Это и есть living documentation.
