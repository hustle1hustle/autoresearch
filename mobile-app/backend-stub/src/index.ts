// REP OAuth stub — holds the GitHub App client secret server-side and proxies
// the code→token and refresh exchanges, so the mobile app never ships a secret.
// Minimal on purpose (dev/test). Production hardening (rate-limit, logging,
// state store, TLS via Caddy/Fly) is a later deliverable.
import express, { type Request, type Response } from "express";

const {
  GITHUB_CLIENT_ID,
  GITHUB_CLIENT_SECRET,
  GITHUB_REDIRECT_URI, // optional; if set, must match the authorize redirect_uri
  PORT = "8787",
} = process.env;

for (const k of ["GITHUB_CLIENT_ID", "GITHUB_CLIENT_SECRET"]) {
  if (!process.env[k]) {
    console.error(`[rep-oauth-stub] missing env ${k} (copy .env.example → .env)`);
    process.exit(1);
  }
}

const GITHUB_TOKEN_URL = "https://github.com/login/oauth/access_token";

type TokenError = { status: number; body: unknown };

async function githubToken(params: Record<string, string>): Promise<any> {
  const res = await fetch(GITHUB_TOKEN_URL, {
    method: "POST",
    headers: { Accept: "application/json", "Content-Type": "application/json" },
    body: JSON.stringify(params),
  });
  const data: any = await res.json().catch(() => ({}));
  if (!res.ok || data?.error) {
    throw { status: res.ok ? 400 : res.status, body: data } as TokenError;
  }
  return data;
}

// Return only what the app needs (GitHub rotates refresh_token on each use).
function pickTokens(d: any) {
  return {
    access_token: d.access_token,
    refresh_token: d.refresh_token ?? null,
    expires_in: d.expires_in ?? null,
    refresh_token_expires_in: d.refresh_token_expires_in ?? null,
    token_type: d.token_type ?? "bearer",
    scope: d.scope ?? "",
  };
}

const app = express();
app.use(express.json());

app.get("/healthz", (_req: Request, res: Response) => res.json({ ok: true }));

// code → tokens.  body: { code, code_verifier?, state? }
app.post("/api/oauth/github/exchange", async (req: Request, res: Response) => {
  const { code, code_verifier } = req.body ?? {};
  if (!code) return res.status(400).json({ error: "missing_code" });
  try {
    const data = await githubToken({
      client_id: GITHUB_CLIENT_ID!,
      client_secret: GITHUB_CLIENT_SECRET!,
      code,
      ...(GITHUB_REDIRECT_URI ? { redirect_uri: GITHUB_REDIRECT_URI } : {}),
      ...(code_verifier ? { code_verifier } : {}), // forwarded if a provider uses PKCE
    });
    res.json(pickTokens(data));
  } catch (e) {
    const err = e as TokenError;
    res.status(err.status ?? 500).json(err.body ?? { error: "exchange_failed" });
  }
});

// refresh_token → rotated tokens.  body: { refresh_token }
app.post("/api/oauth/github/refresh", async (req: Request, res: Response) => {
  const { refresh_token } = req.body ?? {};
  if (!refresh_token) return res.status(400).json({ error: "missing_refresh_token" });
  try {
    const data = await githubToken({
      client_id: GITHUB_CLIENT_ID!,
      client_secret: GITHUB_CLIENT_SECRET!,
      grant_type: "refresh_token",
      refresh_token,
    });
    res.json(pickTokens(data));
  } catch (e) {
    const err = e as TokenError;
    res.status(err.status ?? 500).json(err.body ?? { error: "refresh_failed" });
  }
});

app.listen(Number(PORT), () => {
  console.log(`[rep-oauth-stub] listening on :${PORT}  (client_id=${GITHUB_CLIENT_ID})`);
});
