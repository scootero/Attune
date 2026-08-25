# Pondera: Intentions 1.0 — Scott's Manual Launch Checklist

Last updated: August 6, 2026

This is the controlling checklist for work Scott must do personally in Apple,
GitHub, Cloudflare, or on a physical iPhone. Code and engineering status remain
in `ATTUNE_REMAINING_WORK.md`.

## Fixed release values

| Field | Value |
|---|---|
| App Store name | `Pondera: Intentions` |
| Subtitle | `Are you in tune?` |
| Bundle ID | `com.scottoliver.Pondera.Intentions` |
| Subscription group | `Pondera Premium` |
| Reference name | `Pondera Pro Monthly` |
| Product ID | `com.scottoliver.Attune.monthly` |
| Duration | `1 Month` |
| United States price | `$4.99/month` |
| Introductory trial | **None for version 1.0** |
| Display name | `Pondera Pro Monthly` |
| Description | `Unlimited intentions and check-ins, Listening Sessions, Insights, Momentum history, and data export.` |

Do not create or advertise an introductory offer. Free Pondera is the ongoing
product trial.

## Already complete — do not repeat

- [x] Cloudflare Worker deployed and live-tested.
- [x] OpenAI key kept in the Worker rather than the iPhone app.
- [x] Server-owned `/v2` endpoints deployed and physically verified in Debug.
- [x] In-App Purchase capability and local StoreKit configuration added.
- [x] Subscribe, Restore Purchases, entitlement tracking, Free/Pro gates, and
  Debug Free/Pro/System testing implemented.
- [x] Local product uses `com.scottoliver.Attune.monthly`, $4.99/month, with no trial.
- [x] Phase 1 automated tests passed 16/16; Debug and Release builds passed.
- [x] GitHub Pages-ready landing, Privacy, Support, and Terms files exist under `/docs`.
- [x] App legal links point at the intended GitHub Pages locations.

Do not rotate keys, redeploy the Worker, or edit `Secrets.swift` merely because
an older checklist says to. Only do that for a confirmed credential or deployment need.

## Phase 1 verification you may do now

This is useful but does not replace Apple Sandbox testing later.

- [ ] Install the current Debug build on the physical iPhone without deleting existing data.
- [ ] Settings > Developer > Subscription Access > `Free`.
- [ ] Confirm zero active intentions allows the first intention.
- [ ] Confirm one active intention makes Add open the paywall.
- [ ] Confirm completing today's/this week's target does not free the slot.
- [ ] Confirm removing the active intention allows a replacement.
- [ ] Confirm the Record tab locks Listening Sessions and opens the paywall.
- [ ] Switch to `Pro`; confirm additional intentions and Listening Sessions work.
- [ ] Create multiple intentions in Pro, switch to Free, and confirm all data remains while creation is blocked.
- [ ] Return the selector to `Pro` for normal Debug AI testing, or `System` specifically for StoreKit testing.

## Phase 2 — Do next: App Store Connect and public website

### What Scott must do

Scott owns the account, identity, legal, and final submission decisions below.
Codex can guide each screen and verify the resulting repository/configuration,
but it cannot truthfully mark an external account item complete without Scott's
confirmation or direct evidence.

### A. Account readiness

- [ ] Confirm the Apple Developer Program membership is active.
- [ ] App Store Connect > Agreements, Tax, and Banking: accept the Paid Apps Agreement.
- [ ] Complete banking information.
- [ ] Complete required tax forms.

Status is currently **NEEDS CONFIRMATION**; the repository cannot prove these account items.

How to complete this section:

1. Sign in at <https://developer.apple.com/account/>. Under Membership, confirm
   the membership is active, the correct person/business owns it, and its
   expiration or automatic-renewal status is acceptable.
2. Sign in at <https://appstoreconnect.apple.com>, select **Business**, and open
   **Agreements**. The Account Holder must open the Paid Apps row and accept it.
3. In Business, add or confirm the bank account that should receive Apple's
   payments. Confirm it is not still missing information or awaiting an
   Account Holder approval.
4. Complete every tax form Apple displays for the Paid Apps agreement. A
   US-based individual or business will normally be asked for a US tax form;
   use the actual enrolled legal/tax identity and do not guess.

Recommendation: do this first because account processing can delay subscription
testing even when the app and product configuration are ready.

### B. Support identity and public pages

- [ ] Choose a private support/privacy email address that you are willing to publish.
- [ ] Put that address into the prepared Support and Privacy pages.
- [ ] Approve a checkpoint commit containing the website and current app work.
- [ ] Publish GitHub Pages from the default branch `/docs` folder.
- [ ] Verify the landing, Privacy, Support, and Terms URLs publicly; all four last returned HTTP 404.
- [ ] Confirm every in-app Privacy, Terms, Support, and website link opens the correct public page.

Recommended choices and checks:

- Use one app-specific, monitored inbox for both support and privacy in version
  1.0. An alias such as `attune.support@...` or `support@your-domain...` is
  preferable to publishing a primary personal address. Scott must provide the
  real chosen address; Codex must not invent it.
- GitHub Pages is an acceptable free host, but it is not required by Apple. The
  requirement is that the pages are publicly reachable without a login.
- After publishing, open every URL in Safari on the physical iPhone. Confirm it
  does not return 404, needs no sign-in, identifies Pondera: Intentions, contains the chosen
  contact email, and matches the link opened from inside the app.
- Codex can update the prepared pages and verify them. Scott must approve the
  public email, checkpoint commit/push, and publication decision.

### C. Create the subscription in App Store Connect

- [ ] My Apps > Pondera: Intentions > Monetization > Subscriptions.
- [ ] Rename or confirm subscription group `Pondera Premium`.
- [ ] Create one monthly product using the fixed values above.
- [ ] Set the United States price to $4.99/month.
- [ ] Add the required localization, description, and review screenshot.
- [ ] Do **not** configure an introductory offer or free trial.
- [ ] Confirm the product is in the correct readiness state for Sandbox/TestFlight testing.

How to enter it:

1. App Store Connect > **My Apps** > **Pondera: Intentions** > **Monetization** >
   **Subscriptions**.
2. Rename or confirm the group `Pondera Premium`.
3. Create one auto-renewable subscription using the fixed values at the top of
   this document. Carefully enter the immutable product ID
   `com.scottoliver.Attune.monthly` exactly as shown.
4. Select a one-month duration and the United States $4.99 price point.
5. Add at least the primary English localization, customer-visible display
   name and description, review notes if requested, and an App Review screenshot
   that clearly shows Pondera's paywall and what is being purchased.
6. Leave introductory offers, promotional trials, and free trials unconfigured.

Codex can verify every value against the repository and prepare the text and
screenshot inventory. Scott completes or confirms the App Store Connect entries.

### D. App listing, privacy, and review preparation

- [ ] Enter the live Privacy Policy URL and Support URL in App Store Connect.
- [ ] Provide Terms of Use information. First confirm whether Pondera will use
  Apple's standard Licensed Application End User License Agreement or a custom
  EULA; do not invent or publish a custom legal agreement without approval.
- [ ] Complete App Privacy answers for audio, transcripts/user content, optional mood/wellness-related content where Apple asks, and third-party OpenAI processing through Pondera's Worker.
- [ ] Enter app name `Pondera: Intentions`, then prepare the subtitle, description, keywords, category, age rating, copyright, and contact information.
- [ ] Prepare iPhone screenshots. Pondera 1.0 is configured as an iPhone-only app,
  so native iPad screenshots are not required.
- [ ] Include the paywall/subscription experience in review preparation.
- [ ] Draft App Review notes explaining user-started recording, Apple Speech, AI processing, Free/Pro limits, Subscribe, Restore, and how to reach the demo flows.
- [ ] Create at least one Sandbox Apple Account for later purchase testing.

Recommended choices and checks:

- Use Apple's standard EULA for version 1.0 unless a lawyer or specific
  business requirement calls for a custom EULA. Apple applies its standard EULA
  automatically when no custom EULA is supplied. Keep Pondera's public Terms page
  for the product/subscription explanation.
- Let Codex inspect the implementation and draft the App Privacy answers,
  listing metadata, review notes, and screenshot list. Scott reviews and
  approves them because the App Privacy answers and listing are declarations to Apple.
- Accurately account for user-recorded audio, transcripts/user content,
  mood/wellness-related information where applicable, and processing through
  Pondera's Cloudflare Worker and OpenAI. Separate data kept locally from data
  transmitted for processing.
- Pondera 1.0 is configured for the iPhone device family only. Apple may still
  offer an iPhone-only app on iPad in compatibility mode, but no native iPad
  listing or iPad screenshot set is planned.
- Create the Sandbox tester in App Store Connect under **Users and Access** >
  **Sandbox**. Use a test email that is eligible for a Sandbox account. Later,
  use it on the development-signed physical-iPhone build to test purchase,
  cancellation/failure, renewal/expiration, restore, and reinstall recovery.

### What Codex can do during Phase 2

- [ ] Verify the App Store product identifier matches the app and local StoreKit configuration.
- [ ] Verify the In-App Purchase capability and relevant StoreKit configuration without changing unrelated project settings.
- [ ] Verify the Privacy, Support, Terms, and website URLs used by the app and test the public pages after publication.
- [ ] Insert Scott's approved public contact email into the prepared Markdown/website files.
- [ ] Prepare the exact App Store Connect entry checklist, metadata inventory,
  App Privacy question map, review-note draft, and screenshot inventory without inventing missing values.
- [ ] Run appropriate local build/tests after any approved Phase 2 repository changes.
- [ ] Produce a Phase 2 completion report that separates local verification from
  unverified Sandbox, TestFlight, purchase, expiration, and reinstall behavior.

Stop after Phase 2 and review the results before Phase 3 engineering begins.

## Phase 3 — Plan first, then implement only after approval

Codex's first Phase 3 pass is read-only: inspect the current iOS client and
Worker, then return a narrow file-level proposal. It must cover the request and
authorization flow, server-side entitlement verification, exact files/services,
environment variables and manual configuration, limits, daily ceiling and its
measurement, failure behavior, tests, required launch work, and optional
post-launch hardening. **No Phase 3 code changes occur until Scott approves that
proposal.**

### What is already set up — do not redo it now

- [x] The OpenAI API key is stored in the Cloudflare Worker, not shipped as the
  OpenAI key in the iPhone app.
- [x] The deployed Worker and server-owned task routes work.
- [x] Cloudflare already holds `OPENAI_API_KEY` and the migration-era
  `APP_PROXY_TOKEN`.
- [x] The Worker already has request-body restrictions, server-owned model and
  output controls on `/v2`, timeouts, metadata-only logging, and the
  `AI_ENABLED=false` emergency switch.

Do **not** create a new OpenAI key or redeploy the Worker merely because Phase 3
is approaching. Rotate the key only if exposure is confirmed/suspected or if
Attune is deliberately moved to its own OpenAI project. If a key must be
changed, Scott enters it directly into the Cloudflare secret and never sends it
through chat or commits it.

Required outcomes for the approved minimum implementation:

- Keep the OpenAI key only on the backend; rotate it only if there is evidence it was exposed.
- Remove permanent shared secrets or reusable bearer tokens from the shipped iOS app.
- Apply reasonable request, upload, audio-duration, AI-output, per-install, and application-wide daily limits.
- Use IP throttling only as a secondary abuse control.
- Verify active paid entitlement server-side before costly Pro-only AI operations.
- Preserve recordings and local data when uploads, entitlement checks, or AI requests fail.
- Add useful abuse/usage logging and an emergency spending-disable mechanism.
- Configure OpenAI project budget alerts/spending controls as a manual dashboard step.

Scope restrictions:

- No broad backend rewrite, custom monitoring dashboard, or sophisticated security platform for version 1.0.
- D1 is optional and should be proposed only if it is the simplest justified storage solution; it is not an Apple requirement.
- App Attest is not automatically on the 1.0 critical path. Include it only if it can be isolated and justified without materially delaying launch.
- App Store Server Notifications are optional unless the proposed initial entitlement architecture proves they are necessary.

Most Phase 3 work is engineering work for Codex, not manual work for Scott.
Scott's likely manual actions, only after the approved plan identifies which are required, are:

- [ ] Review and approve the Phase 3 file-level architecture and limits before implementation.
- [ ] In Apple Developer/App Store Connect, enable or confirm only the identifiers and credentials the approved implementation requires.
- [ ] Create App Store server/API credentials only when the Phase 3 implementation identifies the exact current Apple credential type; never paste private keys into chat or commit them.
- [ ] Approve Cloudflare storage/bindings only if the reviewed design justifies them; D1 is not preselected.
- [ ] Add required Cloudflare secrets through the dashboard or `wrangler secret put`; never store secrets in Markdown or Git.
- [ ] Configure OpenAI project budget alerts and spending controls using the approved ceiling.
- [ ] Approve the Worker deployment after tests and reviewed configuration changes pass.
- [ ] Confirm usage limits, abuse thresholds, and emergency-disable behavior match the intended $4.99 plan.

What those conditional actions mean:

- **Apple credential:** this is not the existing OpenAI or Cloudflare secret.
  It would be needed only if the approved backend entitlement design requires
  App Store Server API access. Do not create one before the plan identifies the
  exact current Apple credential and why it is needed.
- **Cloudflare storage/binding:** the current Worker runs, but it does not yet
  keep durable per-install entitlement/usage counters. D1, KV, or another small
  store may be proposed. Do not create D1 in advance.
- **Additional Cloudflare secret:** needed only if the approved design adds an
  Apple server credential or another server-only value. Existing secrets do not
  need to be regenerated just to start the phase.
- **Deployment approval:** Codex can implement and test an approved change, but
  production deployment waits for Scott's explicit approval.

### OpenAI spending protection Scott can configure

First determine whether the existing key belongs to a dedicated Attune OpenAI
project or a shared/default project.

- [ ] In <https://platform.openai.com>, select the project used by the Worker.
- [ ] If it is dedicated to Attune, open **Settings** > **Limits** > **Spend** >
  **Edit spend limit**.
- [ ] During Sandbox/TestFlight, consider a conservative `$25/month` hard limit
  with alerts at 50%, 75%, and 90%; revisit it after measuring real usage.
- [ ] Enable hard-limit enforcement so excess API traffic fails instead of
  continuing indefinitely. Understand that enforcement may allow a small
  propagation overage and that hitting the cap makes Pondera AI temporarily unavailable.
- [ ] If the current project is shared with other applications, do not impose an
  Attune-sized limit on the shared project. The Phase 3 plan should decide
  whether to create a dedicated Attune project and then replace only the
  Worker's `OPENAI_API_KEY` secret.

The dollar value is a starting recommendation for controlled testing, not the
final public-launch budget. The public value should follow measured per-user
cost and the maximum loss Scott is comfortable accepting.

### Minimum required versus optional hardening

Minimum recommended before a public App Store release:

1. Keep the OpenAI key in Cloudflare — already complete.
2. Keep the existing request/model/output/timeout/logging/emergency protections
   and verify their failure behavior — much of this is already complete.
3. Configure OpenAI project alerts and a hard monthly spending limit.
4. Replace the reusable `APP_PROXY_TOKEN` shipped to every app copy; a public
   client token can be extracted and reused to spend Attune's OpenAI budget.
5. Add narrow server-side entitlement and basic persistent usage enforcement so
   one installation cannot consume the entire allowance.
6. Verify AI failures never delete recordings or other local user data.

Not automatically required for version 1.0:

- App Attest.
- App Store Server Notifications.
- A custom monitoring dashboard.
- A broad backend rewrite or sophisticated security platform.
- D1 specifically, unless inspection shows it is the simplest small persistent store.

For private development and Sandbox, the existing setup plus a low hard spend
limit is a reasonable temporary position. Before public release, the shared-token
and basic server usage-control risk should be addressed so an extracted token
cannot exhaust the budget and disable AI for legitimate customers.

Phase 3 must keep Release on the current safe routing until the later TestFlight
release-candidate flow passes. Do not retire the legacy fallback early.

## Later phases — not ready yet

- [ ] Phase 4: local, Sandbox, and physical-device test matrix.
- [ ] Phase 5: archive and test the complete TestFlight release candidate.
- [ ] Phase 6: complete App Store submission only after explicit approval.
- [ ] Phase 7: optional post-launch hardening.

Real purchase, cancellation, pending/interrupted purchase, restore, expiration,
reinstall, localized pricing, and TestFlight behavior remain unverified until
tested in Apple's appropriate environments.

## Exact prompt for the next chat — Phase 2 plus Phase 3 planning

> Continue Pondera from `ATTUNE_REMAINING_WORK.md` and
> `YOUR_REMAINING_STEPS.md`. Inspect Git status first and preserve every
> concurrent change. Complete Phase 2 first: verify the existing StoreKit and
> legal-link configuration, confirm current official Apple requirements, prepare
> the exact App Store Connect values and missing metadata without inventing
> anything, and guide me through my account, public-page, subscription, Sandbox,
> privacy, listing, and review-preparation tasks. Update manual checkboxes only
> when I confirm completion. Version 1.0 is $4.99/month with no introductory
> offer or trial. Return a Phase 2 report before proceeding. After Phase 2 is
> accepted, begin Phase 3 with a read-only inspection of the iOS client and
> Cloudflare Worker and present the narrow file-level security plan required by
> the tracker. Do not change Phase 3 code until I explicitly approve that plan.
> Do not assume D1, App Attest, or App Store Server Notifications are required;
> justify each if proposed. Never request secrets or private keys in chat or Git.
> Keep Release routing unchanged until the complete TestFlight release-candidate
> flow passes.
