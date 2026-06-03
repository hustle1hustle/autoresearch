# Steam · Dota 2 Hours — TLSNotary demo plugin

Proves your **Dota 2 hours on record** from Steam, for testing the TLSNotary mobile/extension plugin app.

## What it does
- Calls `GET https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?access_token=<TOKEN>&input_json={steamid, appids_filter:[570], include_appinfo:true}` — the same call Steam's own web client makes (570 = Dota 2).
- **Auth:** Steam puts the `access_token` in the **URL query** (not a header), so the plugin intercepts it from the request URL (`useHeaders` → `x.url`), not from a `Cookie`/`Authorization` header.
- **Privacy:** it **does not reveal the request line** (which holds the token). The proof reveals only the **response**: `appid` (570), `name` ("Dota 2"), and `playtime_forever`. Trust comes from the TLS server identity (`api.steampowered.com`) + that response.
- `playtime_forever` is in **minutes** → divide by 60 for hours (132900 ≈ 2215 h).

## Build
```bash
npx esbuild steam.plugin.ts --bundle --format=esm --outfile=steam.js \
  --define:__VERIFIER_URL__='"http://localhost:7047"' \
  --define:__PROXY_URL__='"ws://localhost:7047/proxy?token="'
```
(Already built: `steam.js`, ~6.6 kb. Adjust the URLs to your notary/proxy.)

## Test
1. Load `steam.js` into the TLSNotary test app (DevConsole / mobile plugin loader).
2. The plugin opens `steamcommunity.com/my/games/?tab=all` → log into Steam if needed.
3. When the badge shows **"✓ Steam session detected"**, tap **"Prove Dota 2 Hours"**.

## ⚠ One thing to verify in DevTools (couldn't live-test — sandbox allowlist)
Open `https://steamcommunity.com/my/games/?tab=all` with Chrome DevTools → Network → **Fetch/XHR**. Confirm a request to:
```
api.steampowered.com/IPlayerService/GetOwnedGames/...?access_token=...
```
- **If you see it** → the plugin works as-is.
- **If the token comes from** `store.steampowered.com/pointssummary/ajaxgetasyncconfig` (`{"data":{"webapi_token":"..."}}`) **or the games page is server-rendered** (no such XHR) → copy that request **as cURL** and I'll adjust the interception (one-line change).

## Tweaks
- **Different game:** change `DOTA2_APPID` (e.g. Civ V = 8930).
- **Different account:** change `STEAMID` (your SteamID64).
- **Total library / all games:** remove `appids_filter` from `input_json`, raise `maxRecvData` (~70000 like the Garmin example), and note the JSON path index per game is no longer fixed at `0`.
- **Bind the proof to your SteamID** (currently hidden with the token): only do this once the SDK supports redacting a single query param, or move `steamid` out of the tokenized URL.
