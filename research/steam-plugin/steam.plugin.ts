import type { PluginConfig, RequestPermission, Handler, DomJson } from '@tlsn/plugin-sdk';

// Injected at build time via esbuild --define (see packages/plugins/build.js)
declare const __VERIFIER_URL__: string;
declare const __PROXY_URL__: string;

const api = 'api.steampowered.com';
const apiPath = '/IPlayerService/GetOwnedGames/v1/';
const ui = 'https://steamcommunity.com/my/games/?tab=all';

// SteamID64 of the account to prove. Dota 2 appid = 570 (change to prove another game).
const STEAMID = '76561198330186068';
const DOTA2_APPID = 570;

// =============================================================================
// PLUGIN CONFIGURATION
// =============================================================================

const config: PluginConfig = {
  name: 'Steam Dota 2 Hours',
  description: 'This plugin will prove your Dota 2 hours on record on Steam.',
  requests: [
    {
      method: 'GET',
      host: api,
      pathname: apiPath,
      verifierUrl: __VERIFIER_URL__,
    } satisfies RequestPermission,
  ],
  urls: [
    'https://steamcommunity.com/*',
    'https://login.steampowered.com/*',
    'https://store.steampowered.com/*',
    'https://help.steampowered.com/*',
    'https://api.steampowered.com/*',
  ],
};

// =============================================================================
// PROOF GENERATION CALLBACK
// =============================================================================

const onClick = async (): Promise<void> => {
  const isRequestPending = useState<boolean>('isRequestPending', false);
  if (isRequestPending) return;
  setState('isRequestPending', true);

  const token = useState<string | null>('access_token', null);
  if (!token) {
    setState('isRequestPending', false);
    return;
  }

  // Filter to Dota 2 only → tiny response + fixed JSON index (response.games.0.*).
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
    'Accept-Encoding': 'identity',
    Connection: 'close',
  };

  const resp = await prove(
    { url, method: 'GET', headers },
    {
      verifierUrl: __VERIFIER_URL__,
      proxyUrl: __PROXY_URL__ + api,
      maxRecvData: 4096,
      maxSentData: 2048,
      handlers: [
        // IMPORTANT: do NOT reveal SENT START_LINE — the access_token lives in the
        // URL query. The proof binds via the TLS server identity (api.steampowered.com)
        // + the response body (which contains appid 570, name "Dota 2", playtime).
        { type: 'RECV', part: 'START_LINE', action: 'REVEAL' } satisfies Handler,
        {
          type: 'RECV',
          part: 'HEADERS',
          action: 'REVEAL',
          params: { key: 'date' },
        } satisfies Handler,
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
  doneWithOverlay(JSON.stringify(resp));
};

const expandUI = (): void => {
  setState('isMinimized', false);
};

const minimizeUI = (): void => {
  setState('isMinimized', true);
};

// =============================================================================
// MAIN UI FUNCTION
// =============================================================================

const proveProgressBar = (): DomJson[] => {
  const progress = useState<{
    step: string;
    progress: number;
    message: string;
  } | null>('_proveProgress', null);

  if (!progress) return [];

  const pct = `${Math.round(progress.progress * 100)}%`;

  return [
    div({ style: { marginTop: '12px' } }, [
      div(
        {
          style: {
            height: '6px',
            backgroundColor: '#e5e7eb',
            borderRadius: '3px',
            overflow: 'hidden',
          },
        },
        [
          div(
            {
              style: {
                height: '100%',
                width: pct,
                background: 'linear-gradient(90deg, #1b2838, #66c0f4)',
                borderRadius: '3px',
                transition: 'width 0.4s ease',
              },
            },
            [],
          ),
        ],
      ),
      div(
        {
          style: {
            fontSize: '12px',
            color: '#6b7280',
            marginTop: '6px',
            textAlign: 'center',
          },
        },
        [progress.message],
      ),
    ]),
  ];
};

const main = (): DomJson => {
  const isMinimized = useState<boolean>('isMinimized', false);
  const isRequestPending = useState<boolean>('isRequestPending', false);
  const token = useState<string | null>('access_token', null);

  // Steam puts the access_token in the request URL query (not a header),
  // so we read it from the intercepted request URL.
  if (!token) {
    const matches = useHeaders((headers) =>
      headers.filter((h) => h.url.includes('steampowered.com') && h.url.includes('access_token=')),
    );
    const tokenUrl = matches.map((h) => h.url).find((u) => u.includes('access_token='));
    if (tokenUrl) {
      const m = tokenUrl.match(/[?&]access_token=([^&]+)/);
      if (m && m[1]) setState('access_token', decodeURIComponent(m[1]));
    }
  }

  const isConnected = !!token;

  useEffect(() => {
    openWindow(ui);
  }, []);

  if (isMinimized) {
    return div(
      {
        style: {
          position: 'fixed',
          bottom: '20px',
          right: '20px',
          width: '60px',
          height: '60px',
          borderRadius: '50%',
          backgroundColor: '#1b2838',
          boxShadow: '0 4px 8px rgba(0,0,0,0.3)',
          zIndex: '999999',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          cursor: 'pointer',
          transition: 'all 0.3s ease',
          fontSize: '24px',
          color: 'white',
        },
        onclick: 'expandUI',
      },
      ['🎮'], // 🎮
    );
  }

  return div(
    {
      draggable: true,
      style: {
        position: 'fixed',
        bottom: '0',
        right: '8px',
        width: '280px',
        borderRadius: '8px 8px 0 0',
        backgroundColor: 'white',
        boxShadow: '0 -2px 10px rgba(0,0,0,0.1)',
        zIndex: '999999',
        fontSize: '14px',
        fontFamily:
          '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif',
        overflow: 'hidden',
      },
    },
    [
      div(
        {
          style: {
            background: 'linear-gradient(135deg, #1b2838 0%, #66c0f4 100%)',
            padding: '12px 16px',
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            color: 'white',
          },
        },
        [
          div({ style: { fontWeight: '600', fontSize: '16px' } }, ['Steam · Dota 2 Hours']),
          button(
            {
              style: {
                background: 'transparent',
                border: 'none',
                color: 'white',
                fontSize: '20px',
                cursor: 'pointer',
                padding: '0',
                width: '24px',
                height: '24px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
              },
              onclick: 'minimizeUI',
            },
            ['−'],
          ),
        ],
      ),
      div({ style: { padding: '20px', backgroundColor: '#f8f9fa' } }, [
        div(
          {
            style: {
              marginBottom: '16px',
              padding: '12px',
              borderRadius: '6px',
              backgroundColor: isConnected ? '#d4edda' : '#f8d7da',
              color: isConnected ? '#155724' : '#721c24',
              border: `1px solid ${isConnected ? '#c3e6cb' : '#f5c6cb'}`,
              fontWeight: '500',
            },
          },
          [isConnected ? '✓ Steam session detected' : '⚠ Open your Games page to connect'],
        ),
        isConnected
          ? button(
              {
                style: {
                  width: '100%',
                  padding: '12px 24px',
                  borderRadius: '6px',
                  border: 'none',
                  background: 'linear-gradient(135deg, #1b2838 0%, #66c0f4 100%)',
                  color: 'white',
                  fontWeight: '600',
                  fontSize: '15px',
                  cursor: isRequestPending ? 'not-allowed' : 'pointer',
                  transition: 'all 0.2s ease',
                  boxShadow: '0 2px 4px rgba(0,0,0,0.1)',
                  opacity: isRequestPending ? '0.5' : '1',
                },
                onclick: 'onClick',
              },
              [isRequestPending ? 'Generating Proof...' : 'Prove Dota 2 Hours'],
            )
          : div(
              {
                style: {
                  textAlign: 'center',
                  color: '#666',
                  padding: '12px',
                  backgroundColor: '#fff3cd',
                  borderRadius: '6px',
                  border: '1px solid #ffeaa7',
                },
              },
              ['Login to Steam & open your Games page'],
            ),
        ...proveProgressBar(),
      ]),
    ],
  );
};

// =============================================================================
// PLUGIN EXPORTS
// =============================================================================

export default {
  main,
  onClick,
  expandUI,
  minimizeUI,
  config,
};
