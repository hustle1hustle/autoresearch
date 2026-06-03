# 05 — Cookie Probe Procedure (для cookie-path targets)

**Когда нужно.** Перед имплементацией Duolingo, LeetCode, Luma, или любого cookie-path таргета. Cookie name unknown в test-kit ассумпции — нужен real-device probe чтобы capture exact name.

**Что получишь.** Документированные cookie names + atribut'ы для каждого таргета. Permanent data, разово.

**Время.** ~10-15 минут per target. Один раз делаешь для всех.

**Prerequisites.**
- macOS с Safari (Develop menu enabled)
- Active account на каждом таргете
- iOS device (опционально, для cross-verifying)

---

## Why this matters

Cookie-path targets (Duolingo, LeetCode, Luma, LinkedIn) не имеют public OAuth для нужных fact'ов. Мы используем session cookies captured из user's already-logged-in browser session.

Чтобы:
1. Capture правильный cookie (Hack 2 = save to Keychain под biometry)
2. Replay в notarized request (с правильным `Cookie:` header)
3. Test replay durability (Open Question Q5)

Нужно знать **exact cookie name + domain + scope + flags**. Эти details не documented (это session-related internal naming) — только real probe даёт ответ.

---

## Procedure (per target)

### Step 1. Enable Safari Develop menu (если не enabled)

Safari → Settings → Advanced → ✅ "Show Develop menu in menu bar"

### Step 2. Login на target в Safari

Open https://lu.ma (or duolingo.com / leetcode.com / linkedin.com), login normally.

### Step 3. Open Web Inspector

Develop menu → Show Web Inspector (или ⌘⌥I)

### Step 4. Storage tab → Cookies

В Web Inspector:
1. Tab "Storage"
2. Left sidebar → "Cookies" → "[domain]"
3. Display column. Name | Value | Domain | Path | Expires | HttpOnly | Secure | SameSite

### Step 5. Document каждую cookie

Создай table per target. Например для Luma:

```
TARGET: lu.ma

Cookie name        | Domain        | Path | HttpOnly | Secure | SameSite | Notes
-------------------|---------------|------|----------|--------|----------|---------------------
lu_session         | .lu.ma        | /    | ✅       | ✅     | Lax      | likely main session
luma_user_id       | .lu.ma        | /    | ❌       | ✅     | Lax      | identity hint
__cf_bm            | .lu.ma        | /    | ✅       | ✅     | None     | Cloudflare bot mgmt
csrftoken          | .lu.ma        | /    | ❌       | ✅     | Strict   | CSRF protection
```

(Above is **example structure**, actual values to be filled per real probe.)

### Step 6. Identify "session" cookie

Главный session cookie usually:
- HttpOnly = ✅
- Secure = ✅
- Long lifetime (weeks/months expires)
- Name contains "session" / "auth" / "sid" / "token"

CSRF tokens обычно отдельные, могут быть not HttpOnly.

Cloudflare cookies (`__cf_bm`, `cf_clearance`) — это bot-management, не auth. Иногда нужно replay вместе с session cookie чтобы пройти CF.

### Step 7. Make authenticated API request through Safari to verify endpoint

В новом таб Safari → open Web Inspector → Network tab.

Trigger API call в target site (например, navigate to profile page where `event_attended_count` загружается).

Find the XHR request к `api.lu.ma/user/profile` (или соответствующему endpoint).

Click → Headers tab → Request Headers → ищи `Cookie:` header value.

Это **точный** cookie string, который нужно replay. Может содержать несколько cookies separated by `; `.

### Step 8. Document final replay set

```
TARGET: lu.ma
Endpoint: GET https://api.lu.ma/user/profile
Replay cookies needed:
  lu_session=<value>; csrftoken=<value>; __cf_bm=<value>
Other headers required:
  Accept: application/json
  User-Agent: <use realistic Safari UA, see below>
```

### Step 9. Test replay из curl

Чтобы verify cookies работают вне Safari:

```bash
curl -i "https://api.lu.ma/user/profile" \
  -H "Cookie: lu_session=xxx; csrftoken=xxx" \
  -H "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1" \
  -H "Accept: application/json"
```

Expected. 200 OK + JSON body с user profile fields.

Если 401/403:
- Cookie могут IP-pinned (curl с твоего residential IP должен работать)
- Cookie могут UA-pinned (попробуй разные User-Agents)
- Cookie могут expired (re-login и retry)
- Может потребоваться CSRF header (`x-csrf-token: <csrftoken value>`)

### Step 10. Test replay из other network (важно для proxy mode!)

Это валидирует Open Question Q5 для конкретного таргета. Cookie replay survival when source IP меняется.

```bash
# С другого Wi-Fi (например coffee shop, или through HTTP proxy)
curl ... -x http://proxy.example.com:8080
```

Если работает → proxy mode для этого таргета OK (datacenter notary IP не блочится)
Если 401/403 → cookie IP-pinned → нужен MPC mode для этого таргета

Document outcome в `targets/<target>.md` mode recommendation.

---

## Per-target results template

Сохрани в `mobile-app/test-kit/targets/_cookie-probe-results.md`:

```markdown
# Cookie probe results

Date probed: 2026-06-03
Tester: <name>

## Luma
- Endpoint: GET https://api.lu.ma/user/profile
- Cookies: lu_session, csrftoken, [+optional __cf_bm]
- Replay durability (different IP): ✅/❌
- Mode recommendation: proxy / mpc

## Duolingo
- Endpoint: GET https://www.duolingo.com/2017-06-30/users/{id}
- Cookies: jwt_token, [+optional duolingo_user_id]
- Replay durability: ?
- Mode: ?

## LeetCode
- Endpoint: POST https://leetcode.com/graphql
- Cookies: LEETCODE_SESSION, csrftoken
- Headers also needed: x-csrftoken (matching csrftoken value)
- Replay durability: ? (Cloudflare risk)
- Mode: proxy conditional

## LinkedIn
- Endpoint: TBD (likely /voyager/api/identity/profiles/me)
- Cookies: TBD
- Replay durability: ?
- Mode: ?
```

---

## Cross-verification via iOS device

Если хочешь убедиться что Safari Inspector cookie list совпадает с тем что iOS Safari ASWebAuthenticationSession captures:

1. Run host-shell app в Xcode debug mode
2. Trigger cookie capture flow
3. Print captured cookies в console:

```swift
HTTPCookieStorage.shared.cookies(for: URL(string: "https://lu.ma")!)?.forEach { c in
    print("\(c.name) = \(c.value.prefix(20))... [Domain: \(c.domain), Path: \(c.path), HttpOnly: \(c.isHTTPOnly), Secure: \(c.isSecure)]")
}
```

Compare list с Safari Inspector results. Should match.

⚠️ ASWebAuthenticationSession **shares** cookies с Safari (per Apple docs), но в emphemeral session не. `prefersEphemeralWebBrowserSession = false` обязателен для cookie share (см. Hack 3).

---

## Common pitfalls

### Cookie value contains special chars

`Set-Cookie` headers могут содержать `;`, `,`, `=` inside values. Safari может URL-encode'ить их. Replay требует exact bytes.

Fix. capture full `Cookie:` header from Network tab → Request Headers, копируй as-is, don't reformat.

### `__cf_bm` rotates каждые 30 минут

Cloudflare bot-management cookie short-lived. Если ты сохранил его в Keychain через Hack 2 — на replay через day будет expired.

Fix. don't try to persist CF cookies. Capture свежие каждый раз через ASWebAuthSession. Persist только long-lived session cookies.

### Session cookie rotates on activity

Some sites rotate session cookies on each authenticated request (sliding-rotation). Cookies captured вчера могут быть invalid сегодня.

Fix:
- Test replay durability over 24-48 hours
- If fails → re-capture flow needed на every proof (Hack 2 doesn't apply purely; modify flow)
- Document outcome в `targets/<target>.md` notes section

### `HttpOnly` cookies не visible в JS

Safari Inspector shows ALL cookies (including HttpOnly). But если ты пытаешься читать cookies через `document.cookie` в JS — HttpOnly hidden. **Это feature security**. iOS WebView's `WKHTTPCookieStore` всё-таки видит HttpOnly cookies через native API.

### Different cookie names в dev vs prod accounts

Some sites use different cookie naming для beta / paid tier accounts. Test с **regular consumer account**, не enterprise / dev account.

---

## Verify готов (per target)

1. У тебя есть точная list of cookies для replay
2. curl test с этими cookies возвращает 200 OK + JSON
3. Replay through different network (proxy / другой Wi-Fi) — work/fail documented
4. Mode recommendation в `targets/<target>.md` updated
5. Если replay через different network fails → `targets/<target>.md` mode = "mpc" with note

→ Готов имплементить cookie-path таргет в host-shell.

## После probe нескольких targets

Update `test-kit/open-questions.md` Q5 (cookie-replay durability) с per-target results. Это закрывает один из 5 open questions для всех cookie-path Tier-1 targets разом.
