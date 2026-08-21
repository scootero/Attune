# Attune Monthly AI Allowance Handoff

Last updated: August 12, 2026

## What is implemented

- Every iOS Cloudflare request now sends a random anonymous installation ID.
- Cloudflare hashes that ID before storing it; the database never stores the raw ID.
- D1 stores only the hashed installation ID, calendar month, weighted token units,
  request count, and update timestamp.
- No transcript, prompt, quote, extracted item, intention, mood, or other personal
  content is stored in the usage database.
- All `/v1` and `/v2` OpenAI calls reserve usage before calling OpenAI and reconcile
  to OpenAI's actual token usage afterward.
- Failed OpenAI calls release their reservation.
- The app warns once at 80%, shows a clear monthly-limit alert at the cap, and keeps
  all already-saved local data available.
- Talk it out checks the allowance before recording begins so the user is not allowed
  to make a long recording that cannot be processed.

## Initial allowance

- Monthly cap: `10,000,000` weighted units.
- Warning: 80%.
- Weighting: input token = 1 unit; output token = 4 units.
- At GPT-4o mini pricing verified August 12, 2026, the full cap is approximately
  `$1.50` in OpenAI text-token cost per installation per calendar month.
- The cap and warning are Cloudflare variables, so they can be adjusted without an
  App Store update.

## Safe rollout state

`USAGE_LIMIT_MODE` is intentionally configured as `shadow` first. Shadow mode records
usage for updated builds but does not block older installed builds that lack the new
installation header. After the updated app passes physical/TestFlight verification,
change the mode to `enforced` and redeploy the Worker.

Shadow deployment: Worker version `18888ceb-47f5-4ac7-b7be-8a40330257bf`.

Do not claim the cutoff is live while the mode remains `shadow`.

## Verification completed August 12, 2026

- Cloudflare Worker type-check and automated tests: `34/34` passed.
- iOS Simulator test run: `10/10` passed.
- Generic iOS Simulator Debug and Release builds: succeeded.
- Live shadow Worker usage check: succeeded.
- Live synthetic intention request: succeeded.
- D1 inspection confirmed only the anonymous hash and usage counters were stored;
  the synthetic test row was then removed.

## Required deployment order

1. Create/bind the `attune-ai-usage` D1 database.
2. Apply `backend/openai-proxy/migrations/0001_ai_monthly_usage.sql` remotely.
3. Deploy the Worker in `shadow` mode.
4. Install the updated iOS build and verify `/v2/usage`, Check-In, voice intention,
   Talk it out, and suggestion calls.
5. Inspect anonymous D1 totals and confirm no personal content is present.
6. Use a low temporary limit in a non-production test to verify the warning and
   cutoff wording plus Talk it out's preflight block.
7. Restore the approved `10,000,000` limit, change the mode to `enforced`, deploy,
   and repeat a normal AI call.

## Important security boundary

This is a real cost/usage guard for ordinary installed copies, but it is keyed to an
anonymous app-generated installation ID and the existing shared proxy token. A person
who modifies the app could rotate IDs or extract that shared token. Before broad public
launch, pair this with the separately planned server-verified subscription/installation
authorization. App Attest is still optional and should be justified separately rather
than assumed.
