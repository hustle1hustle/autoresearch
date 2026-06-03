# Steam · Dota 2 Hours — TLSNotary plugin

Proves your **Dota 2 hours on record** from Steam. Built and **verified** against the real `tlsnotary/tlsn-extension` monorepo (the mobile app build + plugin build both pass with Steam included).

Files here:
- `steam.plugin.ts` — the plugin (drop into `packages/plugins/src/`). **This is the source of truth.**
- `tlsn-extension-steam.patch` — the 3 one-line wiring edits, ready to `git apply`.
- `steam.js` — a standalone bundle for the **desktop extension DevConsole** path (Path B).

## How it works
- Calls `GET https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?access_token=<T>&input_json={steamid,appids_filter:[570],...}` (570 = Dota 2) — the same call Steam's web client makes.
- **Auth:** Steam puts `access_token` in the **URL query** (not a header) → the plugin reads it from the intercepted request URL (`useHeaders` → `h.url`).
- **Privacy:** it does **not** reveal the request line (that holds the token). It reveals only the response: `appid` (570), `name` ("Dota 2"), `playtime_forever` (**minutes** → ÷60 for hours; 132900 ≈ 2215 h). Trust = TLS server identity (`api.steampowered.com`) + that response.

---

## Path A — build your own mobile app (recommended; this is what you're doing)
Requires a Mac with **Xcode + Node ≥18 + Rust** (per `app/mobile/README.md`).

```bash
# 1. clone the app
git clone https://github.com/tlsnotary/tlsn-extension.git
cd tlsn-extension

# 2. add the plugin
curl -L -o packages/plugins/src/steam.plugin.ts \
  https://raw.githubusercontent.com/hustle1hustle/autoresearch/claude/sleepy-albattani-hDekT/research/steam-plugin/steam.plugin.ts

# 3. apply the 3 wiring edits (build list + both registries)
curl -L -o /tmp/steam.patch \
  https://raw.githubusercontent.com/hustle1hustle/autoresearch/claude/sleepy-albattani-hDekT/research/steam-plugin/tlsn-extension-steam.patch
git apply /tmp/steam.patch

# 4. build & run on iOS
npm install
npm run build:plugins                 # generates dist/mobile/steam.js (STEAM_PLUGIN_CODE)
MOBILE_VERIFIER_URL=https://demo.tlsnotary.org npm run mobile:ios
```

Steam will appear in the **Plugins** gallery. Tap it → it opens your Steam Games page → log in → **Prove Dota 2 Hours**. (Verifier/Proxy come from the app's **Settings** screen — you already have `https://demo.tlsnotary.org` + Proxy mode ON, which is correct.)

### The 3 wiring edits (what the patch does — for manual application)
1. **`packages/plugins/build.js`** — add `'steam'` to the `plugins` array.
2. **`packages/plugins/src/registry.ts`** — add a `steam` entry to `PLUGIN_REGISTRY` with `platforms: ['mobile']` (host `api.steampowered.com`, path `/IPlayerService/GetOwnedGames/v1/`).
3. **`app/mobile/assets/plugins/registry.ts`** — add to `CODE_MAP`:
   ```ts
   steam: () => require('@tlsn/plugins/dist/mobile/steam').STEAM_PLUGIN_CODE,
   ```

---

## Path B — desktop extension DevConsole (no app build)
Use the prebuilt `steam.js` (bundled for `demo.tlsnotary.org`): open the TLSNotary **Chrome extension** → right-click → **Developer Console** → paste the contents of `steam.js` → Enter. (Rebuild with your own verifier via the esbuild command if needed.)

---

## ⚠ One thing to verify in DevTools (I couldn't test live — sandbox host allowlist)
Open `https://steamcommunity.com/my/games/?tab=all` → DevTools → Network → **Fetch/XHR**. Confirm a request to:
```
api.steampowered.com/IPlayerService/GetOwnedGames/...?access_token=...
```
- **Yes** → works as-is.
- **Token comes from** `store.steampowered.com/pointssummary/ajaxgetasyncconfig` (`webapi_token`) **or the page is server-rendered** → send me that request "as cURL" and I'll adjust the interception (one-line change in `main()`).

## Tweaks
- **Another game:** change `DOTA2_APPID` (Civ V = 8930).
- **Another account:** change `STEAMID`.
- **All games / total:** remove `appids_filter` from `inputJson`, raise `maxRecvData` (~70000), and adjust the JSON index (no longer fixed at `0`).
