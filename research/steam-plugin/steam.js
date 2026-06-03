// steam.plugin.ts
var api = "api.steampowered.com";
var apiPath = "/IPlayerService/GetOwnedGames/v1/";
var STEAMID = "76561198330186068";
var DOTA2_APPID = 570;
var C1 = "#1b2838";
var C2 = "#66c0f4";
var config = {
  name: "Steam \xB7 Dota 2 Hours",
  description: "Proves your Dota 2 playtime (hours on record) from Steam",
  requests: [
    {
      method: "GET",
      host: api,
      pathname: apiPath,
      verifierUrl: "http://localhost:7047"
    }
  ],
  urls: ["https://steamcommunity.com/*", "https://api.steampowered.com/*"]
};
var onClick = async () => {
  const isRequestPending = useState("isRequestPending", false);
  if (isRequestPending) return;
  setState("isRequestPending", true);
  const token = useState("access_token", null);
  if (!token) {
    setState("isRequestPending", false);
    return;
  }
  const inputJson = JSON.stringify({
    steamid: STEAMID,
    appids_filter: [DOTA2_APPID],
    include_appinfo: true,
    include_played_free_games: true
  });
  const url = `https://${api}${apiPath}?access_token=${token}&input_json=${encodeURIComponent(inputJson)}&format=json`;
  const headers = {
    Host: api,
    Accept: "application/json",
    "Accept-Encoding": "identity",
    // REQUIRED: no compressed response
    Connection: "close"
    // REQUIRED: clean TLS termination
  };
  const resp = await prove(
    { url, method: "GET", headers },
    {
      verifierUrl: "http://localhost:7047",
      proxyUrl: "ws://localhost:7047/proxy?token=" + api,
      maxRecvData: 4096,
      // 1 game + appinfo ≈ <1KB; buffered
      maxSentData: 2048,
      // URL carries the access_token (JWT ~300 chars)
      handlers: [
        // NOTE: we deliberately DO NOT reveal SENT START_LINE — it contains the
        // access_token. The proof binds via TLS server identity + response body.
        { type: "RECV", part: "START_LINE", action: "REVEAL" },
        {
          type: "RECV",
          part: "HEADERS",
          action: "REVEAL",
          params: { key: "date" }
        },
        // Reveal the proof payload: it's Dota 2, and the hours.
        {
          type: "RECV",
          part: "BODY",
          action: "REVEAL",
          params: { type: "json", path: "response.games.0.appid" }
        },
        {
          type: "RECV",
          part: "BODY",
          action: "REVEAL",
          params: { type: "json", path: "response.games.0.name" }
        },
        {
          type: "RECV",
          part: "BODY",
          action: "REVEAL",
          params: { type: "json", path: "response.games.0.playtime_forever" }
        }
      ]
    }
  );
  done(JSON.stringify(resp));
};
var expandUI = () => {
  setState("isMinimized", false);
};
var minimizeUI = () => {
  setState("isMinimized", true);
};
var proveProgressBar = () => {
  const progress = useState("_proveProgress", null);
  if (!progress) return [];
  const pct = `${Math.round(progress.progress * 100)}%`;
  return [
    div({ style: { marginTop: "12px" } }, [
      div({ style: { height: "6px", backgroundColor: "#e5e7eb", borderRadius: "3px", overflow: "hidden" } }, [
        div({ style: { height: "100%", width: pct, background: `linear-gradient(90deg, ${C1}, ${C2})`, borderRadius: "3px", transition: "width 0.4s ease" } }, [])
      ]),
      div({ style: { fontSize: "12px", color: "#6b7280", marginTop: "6px", textAlign: "center" } }, [progress.message])
    ])
  ];
};
var main = () => {
  const isMinimized = useState("isMinimized", false);
  const isRequestPending = useState("isRequestPending", false);
  const cachedToken = useState("access_token", null);
  if (!cachedToken) {
    const intercepted = useHeaders(
      (h) => h.filter((x) => x.url.includes("steampowered.com") && x.url.includes("access_token="))
    );
    const tokenUrl = intercepted.map((x) => x.url).find((u) => u.includes("access_token="));
    if (tokenUrl) {
      const m = tokenUrl.match(/[?&]access_token=([^&]+)/);
      if (m) setState("access_token", decodeURIComponent(m[1]));
    }
  }
  const isConnected = !!cachedToken;
  useEffect(() => {
    openWindow("https://steamcommunity.com/my/games/?tab=all");
  }, []);
  if (isMinimized) {
    return div({
      style: { position: "fixed", bottom: "20px", right: "20px", width: "60px", height: "60px", borderRadius: "50%", backgroundColor: C1, boxShadow: "0 4px 8px rgba(0,0,0,0.3)", zIndex: "999999", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer", transition: "all 0.3s ease", fontSize: "24px", color: "white" },
      onclick: "expandUI"
    }, ["\u{1F3AE}"]);
  }
  return div({ style: { position: "fixed", bottom: "0", right: "8px", width: "280px", borderRadius: "8px 8px 0 0", backgroundColor: "white", boxShadow: "0 -2px 10px rgba(0,0,0,0.1)", zIndex: "999999", fontSize: "14px", fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif', overflow: "hidden" } }, [
    div({ style: { background: `linear-gradient(135deg, ${C1} 0%, ${C2} 100%)`, padding: "12px 16px", display: "flex", justifyContent: "space-between", alignItems: "center", color: "white" } }, [
      div({ style: { fontWeight: "600", fontSize: "16px" } }, ["\u{1F3AE} Steam \xB7 Dota 2 Hours"]),
      button({ style: { background: "transparent", border: "none", color: "white", fontSize: "20px", cursor: "pointer", padding: "0", width: "24px", height: "24px", display: "flex", alignItems: "center", justifyContent: "center" }, onclick: "minimizeUI" }, ["\u2212"])
    ]),
    div({ style: { padding: "20px", backgroundColor: "#f8f9fa" } }, [
      div({ style: { marginBottom: "16px", padding: "12px", borderRadius: "6px", backgroundColor: isConnected ? "#d4edda" : "#f8d7da", color: isConnected ? "#155724" : "#721c24", border: `1px solid ${isConnected ? "#c3e6cb" : "#f5c6cb"}`, fontWeight: "500" } }, [
        isConnected ? "\u2713 Steam session detected" : "\u26A0 Open your Games page to connect"
      ]),
      isConnected ? button({ style: { width: "100%", padding: "12px 24px", borderRadius: "6px", border: "none", background: `linear-gradient(135deg, ${C1} 0%, ${C2} 100%)`, color: "white", fontWeight: "600", fontSize: "15px", transition: "all 0.2s ease", boxShadow: "0 2px 4px rgba(0,0,0,0.1)", opacity: isRequestPending ? "0.5" : "1", cursor: isRequestPending ? "not-allowed" : "pointer" }, onclick: "onClick" }, [isRequestPending ? "Generating Proof..." : "Prove Dota 2 Hours"]) : div({ style: { textAlign: "center", color: "#666", padding: "12px", backgroundColor: "#fff3cd", borderRadius: "6px", border: "1px solid #ffeaa7" } }, ["Login to Steam & open your Games page"]),
      ...proveProgressBar()
    ])
  ]);
};
var steam_plugin_default = { main, onClick, expandUI, minimizeUI, config };
export {
  steam_plugin_default as default
};
