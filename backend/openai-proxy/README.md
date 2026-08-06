# Attune OpenAI Gateway

Keeps the OpenAI API key off the iOS device. The existing app contract remains
`POST /v1/chat/completions`; the Worker validates Attune's current model,
message, and schema shapes before forwarding the request to OpenAI.

The parallel server-owned v2 contracts are documented in `V2_API.md`. They are
not used by the current iOS build until the later migration phase.

## Local verification

```bash
cd backend/openai-proxy
npm install
npm run check
npx wrangler deploy --dry-run
```

Tests use fake secrets and a mocked OpenAI response. They do not consume API
credits. The dry run builds the deployable Worker but does not publish it.

## Cloudflare secrets and independent key rotation

Production secrets are stored on the deployed Worker, not in this repository:

```bash
npx wrangler secret put OPENAI_API_KEY
npx wrangler secret put APP_PROXY_TOKEN
```

`OPENAI_API_KEY` can be replaced at any time in Cloudflare without changing or
resubmitting the iOS app, provided the Worker URL and HTTP response contract do
not change. Changing the legacy `APP_PROXY_TOKEN` also requires updating the
current app; the planned App Attest migration will remove that shared client
secret.

Generate a long random `APP_PROXY_TOKEN` (for example,
`openssl rand -hex 32`). Put the same value in the app's local, gitignored
`Secrets.swift` as `appProxyToken`. Never commit either secret.

## Deployment (approval required)

From this directory:

```bash
npx wrangler login
npx wrangler deploy
```

Copy the Worker URL into `Secrets.proxyBaseURL` without a trailing slash. A
deployment should be followed by physical-device checks of Voice Check-In,
voice intention creation, and a Listening Session extraction.

## Runtime controls

- `OPENAI_API_KEY`: independently rotatable provider credential.
- `APP_PROXY_TOKEN`: legacy app credential required by the current build.
- `AI_ENABLED=false`: emergency stop; if absent or any other value, AI remains
  enabled for backward compatibility.

The gateway accepts only `gpt-4o-mini`, structured JSON output, the three
schemas currently used by Attune, and requests no larger than 256 KiB. It forces
OpenAI request storage off and logs request metadata only—never transcripts,
prompts, authorization headers, or API keys.

Server-owned task routes:

- `POST /v2/check-ins/extract`
- `POST /v2/intentions/parse`
- `POST /v2/listening/extract`

## Local live-provider testing (optional)

Create a gitignored `.dev.vars` with local test values, then run
`npx wrangler dev`. Do not reuse production credentials unnecessarily.

## iOS Secrets

Copy `Attune/AI/Secrets.swift.example` to `Attune/AI/Secrets.swift` (gitignored)
and fill in `proxyBaseURL` and `appProxyToken`.
