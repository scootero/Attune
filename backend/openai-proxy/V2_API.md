# Attune Server-Owned AI API v2

Status: deployed and live-smoke-tested. Voice intention creation uses v2 in
Debug builds only; Release builds and the other two AI workflows remain on v1.

The v2 routes run beside the existing `/v1/chat/completions` route. They keep
the model, prompts, schemas, storage setting, and output ceilings in the Worker.
During this migration phase they use the existing `APP_PROXY_TOKEN`. App Attest
and server-verified StoreKit entitlement will replace that legacy credential in
a later phase.

## Common request rules

- Method: `POST`
- Header: `Authorization: Bearer <APP_PROXY_TOKEN>`
- Header: `Content-Type: application/json`
- Maximum HTTP body: 256 KiB
- Unknown request fields are rejected.
- Successful responses contain the extracted task JSON directly, not an OpenAI
  Chat Completions envelope.
- Responses include `X-Attune-Request-Id` and
  `X-Attune-Contract-Version: 1`.

Never place real tokens or transcripts in committed fixtures or documentation.

## Monthly AI allowance

`GET /v2/usage` returns the anonymous installation's current calendar-month usage,
warning threshold, limit, and reset date. Updated app builds send
`X-Attune-Installation-Id` on every gateway request. The Worker hashes it before D1
storage and stores usage metadata only—never transcripts or extracted content.

All `/v1` and `/v2` OpenAI calls are counted using actual weighted token usage after
success. Input tokens count as one unit and output tokens as four units, matching the
GPT-4o mini price ratio verified August 12, 2026. Provider failures release their
reservation. The initial cap is 10,000,000 units with an 80% warning and a calendar-
month reset.

The deployed Worker version `18888ceb-47f5-4ac7-b7be-8a40330257bf` runs in `shadow`
mode: it records updated builds but does not block. Change to `enforced` only after
the updated iOS/TestFlight build passes the checklist in `AI_USAGE_LIMIT_HANDOFF.md`.

## Voice Check-In

`POST /v2/check-ins/extract`

```json
{
  "transcript": "I read 10 pages total today. Mood eight out of ten.",
  "intentions": [
    {
      "id": "read-id",
      "title": "Read",
      "aliases": ["reading"],
      "targetValue": 20,
      "unit": "pages",
      "timeframe": "daily"
    }
  ],
  "todaysTotals": {
    "read-id": 5
  }
}
```

Success is the existing structured extraction object:

```json
{
  "updates": [],
  "moodLabel": "Calm",
  "moodScore": 8
}
```

## Voice intention creation

`POST /v2/intentions/parse`

```json
{
  "transcript": "I want to walk 20 minutes every day."
}
```

Success:

```json
{
  "intentions": [
    {
      "title": "Walk",
      "target": 20,
      "unit": "minutes",
      "category": "fitness_health",
      "notes": null
    }
  ]
}
```

## Listening Session extraction

`POST /v2/listening/extract`

```json
{
  "transcript": "I need to call Mom tomorrow.",
  "priorContext": "I was planning my week."
}
```

`priorContext` may be omitted or `null`. Success returns the existing
`{"items": [...]}` extraction object used by `ExtractorService`.

## Recurring-theme small-action suggestion

`POST /v2/intentions/suggest-action`

Deployed August 12, 2026 in Worker version
`9c8c4fb2-e261-4340-a69d-bbab4b05d09f`; authenticated synthetic learning-theme
smoke test returned HTTP 200 with contract version 1 and a catalog-hydrated
retrieval-practice action.

The app sends one already-qualified recurring topic, two to five distinct-session
evidence quotes, active intention titles/aliases, and permanently declined action
IDs. The Worker asks the model to select one allowed action ID or return null,
then validates and hydrates the selection from its curated catalog. The model
cannot invent the title, target, unit, timeframe, source, or safety note.

Success is either `{"suggestion": null}` or a `suggestion` object containing
`actionId`, `title`, `targetValue`, `unit`, `timeframe`, `reason`, supporting
`evidenceItemIds`, and optional source/safety fields.

## Error contract

- `400`: invalid task input
- `401`: missing or invalid migration-phase token
- `413`: HTTP body exceeds 256 KiB
- `415`: request is not JSON
- `429` or another OpenAI error: provider status/body preserved for diagnosis
- `502`: provider network failure or malformed successful response
- `503`: Worker emergency switch is off
- `504`: provider timeout

Errors use `{"error": "message"}` unless the response is a preserved OpenAI
error body.

## Migration sequence

1. ~~Deploy v2 without changing the iOS app.~~ Completed 2026-08-05.
2. ~~Run synthetic requests against all three routes.~~ All returned HTTP 200,
   contract version 1, and the expected response shape on 2026-08-05.
3. ~~Add an iOS v2 client behind a Debug-only switch.~~ Intentions enabled first.
4. Compare v1 and v2 intention results for the same consented test transcripts.
5. Move one feature at a time: intentions, Check-In, then Listening Sessions.
6. Add D1 usage/entitlement records and App Attest request verification.
7. Validate StoreKit transactions server-side and enforce Free/Pro limits.
8. Test through TestFlight before retiring `/v1/chat/completions` and the shared
   proxy token.
