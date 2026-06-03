# REP OAuth stub (dev)

Tiny backend that holds the **GitHub App client secret** and does the OAuth
exchanges the mobile app can't (secret must never ship in the bundle). Unblocks
real token exchange (`setup/06` Phase 2.2) and the item ⑧ flip.

## Endpoints
```
POST /api/oauth/github/exchange   { code, code_verifier?, state? }
   → { access_token, refresh_token, expires_in, refresh_token_expires_in, token_type, scope }

POST /api/oauth/github/refresh    { refresh_token }
   → { access_token, refresh_token (rotated), expires_in, ... }

GET  /healthz → { ok: true }
```
Both proxy `https://github.com/login/oauth/access_token` with the secret added server-side.

## Run locally
```bash
cd mobile-app/backend-stub
cp .env.example .env        # fill GITHUB_CLIENT_ID + GITHUB_CLIENT_SECRET from setup/02 §A
npm install
npm run dev                 # tsx watch, http://localhost:8787
curl localhost:8787/healthz # {"ok":true}
```
> Needs a **GitHub App** (not classic OAuth App) so refresh tokens work — see `../test-kit/setup/02-oauth-apps.md` §A.

## Docker
```bash
docker build -t rep-oauth-stub .
docker run --env-file .env -p 8787:8787 rep-oauth-stub
```

## Fly.io (quick public HTTPS for device testing)
```bash
fly launch --no-deploy        # generates fly.toml (set internal_port = 8787)
fly secrets set GITHUB_CLIENT_ID=Iv1.xxx GITHUB_CLIENT_SECRET=xxx GITHUB_REDIRECT_URI=https://rep.xyz/oauth/github/callback
fly deploy
```
Then point the app at it (below).

## How the iOS app uses it
`GitHubOAuth.swift` (when `Config.useMockAuth = false`):
1. `ASWebAuthenticationSession` → GitHub authorize → Universal-Link callback returns `?code=…&state=…`.
2. App `POST`s `code` to **`Config.githubExchangeURL`** (= `…/api/oauth/github/exchange`) → tokens.
3. Tokens saved to Keychain; warm-returning refresh hits **`Config.githubRefreshURL`** (= `…/api/oauth/github/refresh`).

Set `Config.githubExchangeURL` / `Config.githubRefreshURL` to this server's base (e.g. your Fly URL, or `http://<mac-LAN-ip>:8787` for simulator/device on the same network — add an ATS exception for plain-HTTP LAN if needed).

## Security
- **Secret server-side only.** Never in the app bundle. `.env` is gitignored.
- Dev stub: no rate-limit/auth on the endpoints — don't expose long-term. Production version adds origin checks, rate-limit, and a real state store.
