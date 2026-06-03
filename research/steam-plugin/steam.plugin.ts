// steam.plugin.ts — TLSNotary demo plugin
// Proves your Dota 2 playtime (hours on record) from Steam, without revealing
// your access token. Built against the TLSNotary mobile/extension plugin SDK
// (prove() / useHeaders() / handlers).
//
// ── HOW IT WORKS ──────────────────────────────────────────────────────────
//  • Endpoint:  GET https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/
//               ?access_token=<TOKEN>&input_json={steamid,appids_filter:[570],...}
//    (570 = Dota 2 appid).  This is the same call Steam's own web client makes.
//  • Auth:      access_token is a *query* param (NOT a header). We intercept it
//               from the URL of the browser's api.steampowered.com requests.
//  • Privacy:   we DO NOT reveal the SENT request line (it contains the token).
//               We only reveal the RESPONSE body: appid 570, name "Dota 2",
//               playtime_forever (minutes). The token never enters the proof.
//
// ── THE ONE THING TO VERIFY IN DEVTOOLS (I could not test live) ───────────
//  Open https://steamcommunity.com/my/games/?tab=all  with Chrome DevTools
//  → Network → filter "Fetch/XHR".  Confirm you see a request to
//      api.steampowered.com/IPlayerService/GetOwnedGames/...?access_token=...
//  If yes → this plugin works as-is.
//  If the token instead comes from store.steampowered.com/pointssummary/
//  ajaxgetasyncconfig, or the page is server-rendered (no such XHR), copy that
//  request "as cURL" and I'll adapt the interception. (playtime_forever is in
//  MINUTES → 132900 ≈ 2215 h.)

import type {
  PluginConfig,
  RequestPermission,
  Handler,
  DomJson,
  InterceptedRequestHeader,
} from '@tlsn/plugin-sdk';

declare const __VERIFIER_URL__: string;
declare const __PROXY_URL__: string;

const api = 'api.steampowered.com';
const apiPath = '/IPlayerService/GetOwnedGames/v1/';

// Your SteamID64 (from steamcommunity.com/profiles/<this>). Change to prove a
// different account. Dota 2 appid = 570; change DOTA2_APPID to prove another game.
const STEAMID = '76561198330186068';
const DOTA2_APPID = 570;

const C1 = '#1b2838'; // Steam dark
const C2 = '#66c0f4'; // Steam light blue

const config: PluginConfig = {
  name: 'Steam · Dota 2 Hours',
  description: 'Proves your Dota 2 playtime (hours on record) from Steam',
  requests: [
    {
      method: 'GET',
      host: api,
      pathname: apiPath,
      verifierUrl: __VERIFIER_URL__,
    } satisfies RequestPermission,
  ],
  urls: ['https://steamcommunity.com/*', 'https://api.steampowered.com/*'],
};

const onClick = async (): Promise<void> => {
  const isRequestPending = useState<boolean>('isRequestPending', false);
  if (isRequestPending) return;
  setState('isRequestPending', true);

  const token = useState<string | null>('access_token', null);
  if (!token) {
    setState('isRequestPending', false);
    return;
  }

  // Filter the call to just Dota 2 so the response is tiny and the JSON path
  // is a fixed index (response.games.0.*). Service APIs honor input_json.
  const inputJson = JSON.stringify({
    steamid: STEAMID,
    appids_filter: [DOTA2_APPID],
    include_appinfo: true,
    include_played_free_games: true,
  });
  const url =
    `https://${api}${apiPath}` +
    `?access_token=${token}` +
    `&input_json=${encodeURIComponent(inputJson)}` +
    `&format=json`;

  const headers: Record<string, string> = {
    Host: api,
    Accept: 'application/json',
    'Accept-Encoding': 'identity', // REQUIRED: no compressed response
    Connection: 'close',           // REQUIRED: clean TLS termination
  };

  const resp = await prove(
    { url, method: 'GET', headers },
    {
      verifierUrl: __VERIFIER_URL__,
      proxyUrl: __PROXY_URL__ + api,
      maxRecvData: 4096, // 1 game + appinfo ≈ <1KB; buffered
      maxSentData: 2048, // URL carries the access_token (JWT ~300 chars)
      handlers: [
        // NOTE: we deliberately DO NOT reveal SENT START_LINE — it contains the
        // access_token. The proof binds via TLS server identity + response body.
        { type: 'RECV', part: 'START_LINE', action: 'REVEAL' } satisfies Handler,
        {
          type: 'RECV',
          part: 'HEADERS',
          action: 'REVEAL',
          params: { key: 'date' },
        } satisfies Handler,
        // Reveal the proof payload: it's Dota 2, and the hours.
        {
          type: 'RECV',
          part: 'BODY',
          action: 'REVEAL',
          params: { type: 'json', path: 'response.games.0.appid' },
        } satisfies Handler,
        {
          type: 'RECV',
          part: 'BODY',
          action: 'REVEAL',
          params: { type: 'json', path: 'response.games.0.name' },
        } satisfies Handler,
        {
          type: 'RECV',
          part: 'BODY',
          action: 'REVEAL',
          params: { type: 'json', path: 'response.games.0.playtime_forever' },
        } satisfies Handler,
      ],
    },
  );

  done(JSON.stringify(resp));
};

const expandUI = (): void => { setState('isMinimized', false); };
const minimizeUI = (): void => { setState('isMinimized', true); };

const proveProgressBar = (): DomJson[] => {
  const progress = useState<{ step: string; progress: number; message: string } | null>('_proveProgress', null);
  if (!progress) return [];
  const pct = `${Math.round(progress.progress * 100)}%`;
  return [
    div({ style: { marginTop: '12px' } }, [
      div({ style: { height: '6px', backgroundColor: '#e5e7eb', borderRadius: '3px', overflow: 'hidden' } }, [
        div({ style: { height: '100%', width: pct, background: `linear-gradient(90deg, ${C1}, ${C2})`, borderRadius: '3px', transition: 'width 0.4s ease' } }, []),
      ]),
      div({ style: { fontSize: '12px', color: '#6b7280', marginTop: '6px', textAlign: 'center' } }, [progress.message]),
    ]),
  ];
};

const main = (): DomJson => {
  const isMinimized = useState<boolean>('isMinimized', false);
  const isRequestPending = useState<boolean>('isRequestPending', false);
  const cachedToken = useState<string | null>('access_token', null);

  // Intercept the access_token from the URL of api.steampowered.com requests.
  // (Steam puts it in the query string, not a header — so we read x.url.)
  if (!cachedToken) {
    const intercepted = useHeaders((h: InterceptedRequestHeader[]) =>
      h.filter((x) => x.url.includes('steampowered.com') && x.url.includes('access_token=')),
    );
    const tokenUrl = intercepted.map((x) => x.url).find((u) => u.includes('access_token='));
    if (tokenUrl) {
      const m = tokenUrl.match(/[?&]access_token=([^&]+)/);
      if (m) setState('access_token', decodeURIComponent(m[1]));
    }
  }

  const isConnected = !!cachedToken;

  // Open the user's Games page (prompts login if needed) so the browser fires
  // the GetOwnedGames XHR that carries the access_token.
  useEffect(() => {
    openWindow('https://steamcommunity.com/my/games/?tab=all');
  }, []);

  if (isMinimized) {
    return div({
      style: { position: 'fixed', bottom: '20px', right: '20px', width: '60px', height: '60px', borderRadius: '50%', backgroundColor: C1, boxShadow: '0 4px 8px rgba(0,0,0,0.3)', zIndex: '999999', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', transition: 'all 0.3s ease', fontSize: '24px', color: 'white' },
      onclick: 'expandUI',
    }, ['🎮']);
  }

  return div({ style: { position: 'fixed', bottom: '0', right: '8px', width: '280px', borderRadius: '8px 8px 0 0', backgroundColor: 'white', boxShadow: '0 -2px 10px rgba(0,0,0,0.1)', zIndex: '999999', fontSize: '14px', fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif', overflow: 'hidden' } }, [
    div({ style: { background: `linear-gradient(135deg, ${C1} 0%, ${C2} 100%)`, padding: '12px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: 'white' } }, [
      div({ style: { fontWeight: '600', fontSize: '16px' } }, ['🎮 Steam · Dota 2 Hours']),
      button({ style: { background: 'transparent', border: 'none', color: 'white', fontSize: '20px', cursor: 'pointer', padding: '0', width: '24px', height: '24px', display: 'flex', alignItems: 'center', justifyContent: 'center' }, onclick: 'minimizeUI' }, ['−']),
    ]),
    div({ style: { padding: '20px', backgroundColor: '#f8f9fa' } }, [
      div({ style: { marginBottom: '16px', padding: '12px', borderRadius: '6px', backgroundColor: isConnected ? '#d4edda' : '#f8d7da', color: isConnected ? '#155724' : '#721c24', border: `1px solid ${isConnected ? '#c3e6cb' : '#f5c6cb'}`, fontWeight: '500' } }, [
        isConnected ? '✓ Steam session detected' : '⚠ Open your Games page to connect',
      ]),
      isConnected
        ? button({ style: { width: '100%', padding: '12px 24px', borderRadius: '6px', border: 'none', background: `linear-gradient(135deg, ${C1} 0%, ${C2} 100%)`, color: 'white', fontWeight: '600', fontSize: '15px', transition: 'all 0.2s ease', boxShadow: '0 2px 4px rgba(0,0,0,0.1)', opacity: isRequestPending ? '0.5' : '1', cursor: isRequestPending ? 'not-allowed' : 'pointer' }, onclick: 'onClick' }, [isRequestPending ? 'Generating Proof...' : 'Prove Dota 2 Hours'])
        : div({ style: { textAlign: 'center', color: '#666', padding: '12px', backgroundColor: '#fff3cd', borderRadius: '6px', border: '1px solid #ffeaa7' } }, ['Login to Steam & open your Games page']),
      ...proveProgressBar(),
    ]),
  ]);
};

export default { main, onClick, expandUI, minimizeUI, config };
