# Attune OpenAI Proxy

Keeps the OpenAI API key off the iOS device. The app calls this Worker with an app proxy token; the Worker adds the real OpenAI key and forwards `/v1/chat/completions`.

## One-time setup

1. Install Wrangler (or use npx): `npm i -g wrangler`
2. Log in: `npx wrangler login`
3. From this folder, deploy:

```bash
cd backend/openai-proxy
npx wrangler deploy
```

4. Set secrets (use a **new** OpenAI key after revoking the old exposed one):

```bash
npx wrangler secret put OPENAI_API_KEY
npx wrangler secret put APP_PROXY_TOKEN
```

Generate a long random `APP_PROXY_TOKEN` (e.g. `openssl rand -hex 32`). Put the same value in the app’s local `Secrets.swift` as `appProxyToken`.

5. Copy the Worker URL from the deploy output into `Secrets.proxyBaseURL` (no trailing slash), e.g. `https://attune-openai-proxy.<your-subdomain>.workers.dev`.

## Local test

```bash
# Create .dev.vars with OPENAI_API_KEY and APP_PROXY_TOKEN
npx wrangler dev
```

## iOS Secrets

Copy `Attune/AI/Secrets.swift.example` → `Attune/AI/Secrets.swift` (gitignored) and fill in `proxyBaseURL` + `appProxyToken`.
