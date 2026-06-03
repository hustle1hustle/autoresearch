# 02 — OAuth App Setup (GitHub + Strava + StackOverflow)

**Когда нужно.** Item ③ PLAN.md. OAuth+PKCE flow для Tier-1 OAuth таргетов.

**Что получишь.** Готовые Client IDs, callback URLs, и refresh-token configuration для трёх OAuth-based Tier-1 platforms.

**Время.** ~30-45 минут на все три (большая часть — ожидание email confirmation для StackOverflow).

**Prerequisites.**
- GitHub account
- Strava account
- StackOverflow account
- Уже задеплоен `rep.xyz` (или решено что callback host — пока какой)

---

## Decision. callback host

Все три OAuth apps требуют HTTPS redirect URI для Universal Link auto-return (Hack 4). Варианты:

| Option | Pros | Cons | Когда выбирать |
|---|---|---|---|
| `https://rep.xyz/oauth/<target>/callback` | Production-ready, готов под AASA | Требует deployed domain | **Recommended.** Если rep.xyz уже live |
| `https://rep-dev.<your-dev-domain>/oauth/<target>/callback` | Dev separation от prod | Doubles AASA work | Если хочешь чёткий dev/prod split |
| Temporary `https://oauth.ngrok.io` | Quick start без своего хоста | Меняется при restart ngrok | Только для самого первого "does it work" теста |

**Рекомендация для kit.** Используй `https://rep.xyz/oauth/<target>/callback`. Hosting AASA — отдельная задача в [04-universal-links.md](04-universal-links.md), но нечего откладывать.

---

## A. GitHub OAuth App (HERO)

### Создание

1. Открой https://github.com/settings/developers (Settings → Developer settings → OAuth Apps)
2. **New OAuth App**
3. Заполни:
   - **Application name.** `REP (dev)` или `REP iOS`
   - **Homepage URL.** `https://rep.xyz`
   - **Application description.** `Mint verifiable proofs of your GitHub data via zkTLS. Mobile.`
   - **Authorization callback URL.** `https://rep.xyz/oauth/github/callback`
4. Tap **Register application**

### Получи credentials

После создания страница покажет:
- **Client ID.** `Iv1.xxxxxxxxxxxxxxxx` (public, OK в mobile bundle)
- **Generate a new client secret** → нажми → получишь `ghp_xxxxxxxxxxxxxxxxxxxxxx`
  - ⚠️ Server-side ONLY. Не bundle в mobile app. Сохрани в secure storage (1Password / Bitwarden / env var).

### Enable refresh tokens

В OAuth App settings найди и enable:
- ✅ **"Enable Device Flow"** — оставь выключенным (не используем)
- ✅ **Trade-off opt-in для refresh tokens.** GitHub OAuth Apps **по-умолчанию НЕ выдают refresh tokens** — нужно explicitly opt in.

Чтобы получить refresh_token в response, OAuth app должна быть **GitHub App**, не классическая **OAuth App**. **Это разные типы apps в GitHub.**

#### Decision. OAuth App vs GitHub App

| | OAuth App | GitHub App |
|---|---|---|
| Refresh tokens | ❌ no (per [docs](https://docs.github.com/en/apps/oauth-apps)) | ✅ yes ([refresh docs](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/refreshing-user-access-tokens)) |
| Token expiration | Never (until revoked) | 8 hours access, 6 months refresh |
| Scopes | broad OAuth scopes | fine-grained permissions |
| User installation | per-account | per-account or per-repo |
| Best для | classic OAuth flow | modern, security-focused |

**Recommendation для REP.** Используй **GitHub App**, не OAuth App. Хотя docs ссылаются на "OAuth Apps", refresh tokens работают только в GitHub Apps.

### Создание GitHub App вместо OAuth App

1. Открой https://github.com/settings/apps (Settings → Developer settings → GitHub Apps)
2. **New GitHub App**
3. Заполни:
   - **GitHub App name.** `REP (dev)` или `REP iOS Dev`
   - **Description.** Same as before
   - **Homepage URL.** `https://rep.xyz`
   - **Callback URL.** `https://rep.xyz/oauth/github/callback`
   - ✅ **Expire user authorization tokens** — checked
   - ✅ **Request user authorization (OAuth) during installation** — checked
   - **Webhook.** Active → uncheck (не нужно для proof flow)
   - **Permissions.** User permissions →
     - **Email addresses.** Read-only (если нужно для identity verification)
     - **Profile.** Read-only
     - **Followers.** Read-only (для composability с другими proofs)
   - **Where can this GitHub App be installed?** Any account
4. Tap **Create GitHub App**

### Получи credentials (GitHub App)

- **App ID.** integer, public
- **Client ID.** `Iv1.xxxxxxxxxxxxxxxx` (public)
- **Client secret.** generate → keep server-side
- **Private key.** generate `.pem` file → keep server-side (только если используем app-side auth, не user-side)

### Verify scopes

Default user-installation flow даст app `read:user` scope automatically через User permissions выше. Verify:
1. Install app на тестовый account
2. Через PKCE flow получи token
3. `curl -H "Authorization: Bearer <token>" https://api.github.com/user`
4. Должно вернуть user profile

### Test refresh flow

После first OAuth:
```bash
curl -X POST https://github.com/login/oauth/access_token \
  -H "Accept: application/json" \
  -d "client_id=Iv1.xxx" \
  -d "client_secret=xxx" \
  -d "grant_type=refresh_token" \
  -d "refresh_token=ghr_xxx"
```

Response должна содержать:
```json
{
  "access_token": "ghs_xxx",
  "expires_in": 28800,
  "refresh_token": "ghr_xxx",          ← rotated, нужно сохранить
  "refresh_token_expires_in": 15897600,
  "token_type": "bearer",
  "scope": "..."
}
```

Если работает — Hack 2 имплементируем.

---

## B. Strava OAuth App

### Создание

1. Открой https://www.strava.com/settings/api (нужен Strava account)
2. **Create & Manage Your App**
3. Заполни:
   - **Application Name.** `REP`
   - **Category.** Other
   - **Club.** оставь пустым
   - **Website.** `https://rep.xyz`
   - **Application Description.** `Mint verifiable proofs of your Strava activities via zkTLS.`
   - **Authorization Callback Domain.** `rep.xyz` (⚠️ ТОЛЬКО domain, не full path)
4. Upload icon (опционально, но recommended для production-feel)
5. Tap **Create**

### Получи credentials

- **Client ID.** integer (public, OK in mobile bundle)
- **Client Secret.** keep server-side
- **Access Token.** initial single-user token для testing (можешь использовать для verification что API работает)
- **Refresh Token.** automatically rotated on each refresh

### Test PKCE flow

В iOS app используй mobile deep-link:

```swift
let authURL = "strava://oauth/mobile/authorize" +
    "?client_id=\(clientID)" +
    "&redirect_uri=https://rep.xyz/oauth/strava/callback" +
    "&response_type=code" +
    "&approval_prompt=auto" +
    "&scope=activity:read" +
    "&code_challenge=\(pkce.challenge)" +
    "&code_challenge_method=S256"
```

Если Strava app не установлена, fallback на web:
```
https://www.strava.com/oauth/mobile/authorize?...
```

### Scope. activity:read vs activity:read_all

- `activity:read` — public activities only
- `activity:read_all` — incl. private activities

**Recommendation.** Запроси `activity:read` для v1. Меньше friction в consent screen.

---

## C. StackOverflow OAuth App (Stack Apps)

### Создание

1. Открой https://stackapps.com/apps/oauth/register
2. Заполни:
   - **Application Name.** `REP`
   - **Description.** `Mint verifiable proofs of your StackOverflow reputation via zkTLS.`
   - **OAuth Domain.** `rep.xyz`
   - **Application Website.** `https://rep.xyz`
   - **Use Stack Exchange API access tokens.** check (опционально для read-only)
   - **Enable Client Side OAuth Flow.** ✅ check (для PKCE)
3. Tap **Register Your Application**

### Получи credentials

- **Client ID.** integer (public)
- **Client Secret.** keep server-side
- **Key.** application key (semi-public — нужен в каждом API request)

### Authorize URL

```swift
let authURL = "https://stackoverflow.com/oauth" +
    "?client_id=\(clientID)" +
    "&scope=read_inbox" +
    "&redirect_uri=https://rep.xyz/oauth/stackoverflow/callback" +
    "&state=\(state)" +
    "&code_challenge=\(pkce.challenge)" +
    "&code_challenge_method=S256"
```

### Token expiration nuance

Stack Apps OAuth tokens **never expire by default** (unlike GitHub). Это значит:
- Hack 2 модифицирован для SO. сохраняем `access_token` (не `refresh_token`) в Keychain
- Не нужен refresh flow для repeat proofs
- Юзер revoke только manual в Stack Exchange settings

---

## D. (Future) Anthropic Console — admin key

Не OAuth flow. Юзер pastes admin API key (`sk-ant-admin-...`) непосредственно. См. [`../targets/anthropic.md`](../targets/anthropic.md) для UX flow.

Pre-condition. user должен быть org admin в Anthropic Console и создать admin key через https://console.anthropic.com/settings/keys.

---

## Summary table. сохрани в credentials store

После завершения 02-A, B, C у тебя должно быть:

| Target | Client ID | Client Secret | Callback URL | Scope |
|---|---|---|---|---|
| GitHub | `Iv1.xxx` | `ghp_xxx` | `https://rep.xyz/oauth/github/callback` | (via app permissions) |
| Strava | `<integer>` | `<hex string>` | `https://rep.xyz/oauth/strava/callback` (domain `rep.xyz`) | `activity:read` |
| StackOverflow | `<integer>` | `<hex string>` + Key | `https://rep.xyz/oauth/stackoverflow/callback` | `read_inbox` |

**Где хранить.**
- Client IDs → в iOS app bundle (public, OK)
- Client Secrets → **NEVER** в mobile bundle. Server-side env vars / Vault / 1Password.
- Strava Application Key → semi-public, можно в bundle

**В test-kit.** Создай `tlsn-build/.env.example` с placeholders:
```
GITHUB_CLIENT_ID=Iv1.replace_me
STRAVA_CLIENT_ID=replace_me
STACKOVERFLOW_CLIENT_ID=replace_me
STACKOVERFLOW_KEY=replace_me
```

И реальный `.env` (gitignored).

---

## Common pitfalls

### "redirect_uri_mismatch"

Точное совпадение требуется. `https://rep.xyz/oauth/github/callback` ≠ `https://rep.xyz/oauth/github/callback/` (trailing slash). Verify exact match в OAuth app settings.

### GitHub. `incorrect_client_credentials`

Client Secret тонкий. без пробелов до/после, exact case. Регенерируй если непонятно.

### Strava. "Connection Error" в Strava app

Strava app deep-link sometimes hangs. Fallback на web OAuth. См. open question по Strava mobile OAuth UX в `../targets/strava.md`.

### StackOverflow consent screen mentions "key" but you didn't provide one

Stack Apps OAuth flow требует `&key=<your-app-key>` в каждом API request (post-token). Token alone недостаточен. Document в host-shell wiring.

### Refresh token не возвращается (GitHub)

Используешь OAuth App вместо GitHub App. Refresh tokens только в GitHub Apps. Создай заново как GitHub App (см. выше).

---

## Verify ready

После всех трёх:
1. У тебя есть 3 Client IDs в `.env`
2. У тебя есть 3 Client Secrets в secure storage
3. Callback URLs зарегистрированы в OAuth app settings
4. Test curl request к `https://api.github.com/user` с manually-obtained access token работает

→ Готов имплементировать Hack 4 ([04-universal-links.md](04-universal-links.md)) поверх этих OAuth apps.
