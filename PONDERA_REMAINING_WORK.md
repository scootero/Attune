# Attune Remaining Work

Last updated: August 6, 2026

This is the concise tracker for the work remaining after completion of UI Phases 0–6. The detailed history and verification log remain in `PONDERA_UI_RELEASE_PLAN.md`.

## Current position

- Phases 0–6 are implemented at the UI level.
- The approved Free/Pro model is implemented: Free has one active intention,
  one Voice Check-In per day, today's Momentum only, and a free 6 PM reminder.
- Pro unlocks additional intentions, unlimited check-ins, Listening Sessions,
  Insights, Momentum history/Week/Month, voice intention setup, and export.
- Free Home and Momentum expose only today's progress; the weekly Home preview is Pro-only.
- The local StoreKit product is configured for $4.99/month with no introductory
  trial. The same product and price still must be created in App Store Connect.
- Momentum Day, Week, Month, and Progress History have been tested with removable simulator-only demo data.
- The hardened Cloudflare gateway and all three server-owned `/v2` task
  endpoints are deployed. Live synthetic smoke tests passed for voice
  intentions, Voice Check-In, and Listening Session extraction.
- The iOS Debug build now uses all three server-owned task routes:
  `/v2/intentions/parse`, `/v2/check-ins/extract`, and
  `/v2/listening/extract`. Release remains entirely on `/v1` until staged
  physical-device verification is complete.
- Physical-iPhone verification passed for voice intentions, Voice Check-In,
  and Listening Sessions. Phase 1 Free/Pro implementation and local tests are
  complete. The next approved phase is Phase 2 App Store Connect and public
  website setup; production AI security follows only in Phase 3.
- `YOUR_REMAINING_STEPS.md` is the controlling checklist for Scott's manual
  account, website, Sandbox, TestFlight, and submission actions.

## Phase 6 — Settings, onboarding, privacy, and paywall

- [x] Reorganize Settings into Membership, Notifications, Privacy & Data, and Support.
- [x] Show microphone, speech-recognition, and notification permission status with an iOS Settings entry point.
- [x] Replace the confusing export wording about “training purposes.”
- [x] Add a short, benefit-focused first-run onboarding flow.
- [ ] Clearly disclose AI processing and privacy without overwhelming the user.
- [x] Professionally brand the Pondera Pro subscription/paywall screen.
- [x] Polish StoreKit unavailable, loading, and error states.
- [x] Polish About, Support, Privacy, Terms, and data-request entry points.

The final AI-disclosure checkbox stays open until the staged gateway rollout
and provider wording are complete. Release behavior has not changed; all three
Debug AI paths are currently opted into their server-owned `/v2` routes.

## Decisions needed before Phase 7

- [x] Approve hardening the existing Cloudflare Worker as Pondera's production AI gateway.
- [x] Free/Pro limits approved and implemented as described above.
- [ ] Approve final provider-specific privacy wording after the gateway design is settled.

## Production AI gateway rollout

- [x] Preserve the current `/v1/chat/completions` app contract.
- [x] Add model/schema/body limits, timing-safe legacy-token validation, provider timeout handling, request-storage prevention, an emergency switch, and metadata-only logs.
- [x] Add local Cloudflare-runtime contract tests and a no-deploy build check.
- [x] Review, deploy, and live-verify the hardened legacy endpoint.
- [x] Validate all three AI flows on a physical device after deployment.
- [x] Add, deploy, and live-smoke-test parallel server-owned task endpoints for
  Check-In, voice intentions, and Listening Session extraction.
- [x] Add the iOS `/v2` client behind per-feature Debug-only switches and enable
  voice intention parsing first.
- [x] Verify voice intention parsing on a physical iPhone.
- [x] Enable and verify Check-In through `/v2`.
- [x] Enable Listening Sessions through `/v2` in Debug.
- [x] Verify Listening Sessions through `/v2` on a physical iPhone.
- [ ] Before Phase 3 code, inspect the current client/Worker and obtain approval
  for a minimum server authorization, entitlement, usage-limit, and spending-control plan.
- [ ] Remove shipped reusable backend credentials and add server-side entitlement
  verification plus reasonable per-install, request, duration, output, and daily ceilings.
- [x] Implement a privacy-minimal, configurable monthly AI allowance with 80% warning,
  friendly cutoff handling, and Talk it out preflight. It remains in Cloudflare shadow
  mode until the updated build and D1 path pass physical/TestFlight verification; see
  `AI_USAGE_LIMIT_HANDOFF.md`.
- [ ] Evaluate App Attest, D1, and App Store Server Notifications individually;
  use them only when the approved version 1.0 design justifies them.
- [ ] Move the iOS client to the task endpoints, validate in TestFlight, then retire the shared `APP_PROXY_TOKEN` path.

The Cloudflare `OPENAI_API_KEY` remains independently rotatable without an app
update. The Worker is deployed, and Debug-only intention, Check-In, and
Listening endpoint routing is implemented. No D1 binding, App Attest
validation, server-side StoreKit verification, or Release/TestFlight `/v2`
migration has been made yet.

## Phase 7 — Accessibility and release QA

- [ ] Audit VoiceOver labels and hints.
- [x] Ensure statuses are understandable without relying only on color.
- [ ] Test Dynamic Type, contrast, Reduce Motion, and touch-target sizes.
- [x] Check small and large iPhone layouts.
- [x] Check iPad layouts.
- [ ] Test offline behavior and denied permissions.
- [x] Test processing failure and recovery states.
- [x] Test StoreKit failure and recovery states locally; App Store Sandbox remains below.
- [ ] Configure and verify the $4.99/month product with no introductory trial in App Store Connect/Sandbox.
- [ ] Complete final Debug and Release builds.
- [ ] Review App Store metadata, privacy disclosures, and legal/support links.

### Phase 7 checkpoint — August 5, 2026

- Core Home controls, progress, mood, streak, weekly chart, denied-permission,
  recording, and processing-failure states expose descriptive accessibility
  text. A full physical-device VoiceOver navigation pass is still required.
- Largest Accessibility Dynamic Type, Increase Contrast, non-color status
  communication, and Reduce Motion-sensitive animations were audited. Home
  headers/cards now stack at accessibility sizes; paywall legal and Restore
  controls retain 44-point touch height. A physical Reduce Motion/VoiceOver
  pass remains before release.
- Simulator layouts passed on iPhone 17e, iPhone 17 Pro, iPhone 17 Pro Max, and
  iPad mini. The denied-microphone state passed with visible Open Settings and
  Not Now actions.
- A real Simulator Check-In advanced its recording timer to 0:03, showed the
  expected recoverable speech-recognition failure with Try Again, and returned
  automatically to the idle control. Offline transport recovery still needs a
  real-device/network test.
- Local StoreKit configuration was rechecked at
  `com.scottoliver.Pondera.Intentions.monthly`, $4.99/month, with no introductory trial.
  App Store Connect/Sandbox configuration is still external and unverified.
- Current-source generic-device Debug and Release builds passed after the QA
  fixes. Re-run both after Listening `/v2`, security, and TestFlight changes;
  those later builds are the final release gate.
- All four configured GitHub Pages URLs currently return HTTP 404, and the
  Support page still requires a private support/privacy email. App Store
  metadata and App Privacy answers are therefore not release-ready yet.

## Physical-device verification

These flows are implemented but cannot be completely proven in the iOS Simulator.

### Phase 1 Free/Pro checklist — pending physical iPhone and Sandbox

- [ ] In a Debug build, open Settings > Developer and select `Free`.
- [ ] With zero active intentions, create the first intention and confirm it saves.
- [ ] With one active intention, tap Add and confirm the Pondera Pro paywall opens.
- [ ] Remove the active intention, save, reopen Intentions, and confirm a replacement can be created.
- [ ] Confirm reaching 100% daily or weekly progress does not free the active-intention slot.
- [ ] On the Record tab, confirm Free shows the Listening Sessions lock and its CTA opens the paywall.
- [ ] Select `Pro`; confirm another intention can be created and Listening Sessions can start after permissions.
- [ ] Create multiple intentions in Pro, switch to `Free`, and confirm all existing data remains readable/editable while Add is blocked until the active set is within the Free limit.
- [ ] Select `System`; use an Apple Sandbox account to verify purchase, cancellation, pending/interrupted purchase, restore, expiration, reinstall, and entitlement recovery.
- [ ] Confirm the Apple purchase sheet shows `com.scottoliver.Pondera.Intentions.monthly` at the localized equivalent of $4.99/month with no introductory trial.

Automated Phase 1 coverage passed 16/16 tests on the iPhone 17 Pro simulator.
Generic Debug simulator and unsigned Release-device builds passed. These local
results do not verify real Apple Sandbox, TestFlight, reinstall, or expiration behavior.

- [x] Verify successful Voice Check-In transcription and saved-result UI.
- [x] Verify successful Listening Session transcription.
- [x] Verify Debug voice intention creation through `/v2/intentions/parse` on a
  physical iPhone.
- [x] Verify Debug Voice Check-In extraction through `/v2/check-ins/extract` on
  a physical iPhone.
- [ ] Test a real phone/audio interruption, background recovery, and continued processing.

## Exact next handoff

1. Open `YOUR_REMAINING_STEPS.md`; optionally complete its Phase 1 physical
   Free/Pro checklist, then begin Phase 2 manual App Store Connect and website work.
2. Verify each external account action before marking it complete. Current
   unknowns include Apple membership, agreements/tax/banking, support email,
   GitHub Pages publication, subscription creation, and App Privacy answers.
3. Stop after the Phase 2 report. Do not begin App Attest, server-side
   StoreKit verification, usage accounting, or other Phase 3 AI-security code
   without first presenting and receiving approval for the narrow file-level plan.
   Do not preselect App Attest, D1, or App Store Server Notifications.
   Keep Release routing intact until the complete TestFlight release-candidate flow passes.

### Voice Check-In physical test checklist

- [x] Install the current Debug build over the existing physical-iPhone app
  without deleting it, so existing Attune data remains intact.
- [x] Confirm the Xcode console shows
  `v2_request_start task=/v2/check-ins/extract` followed by
  `v2_response_received task=/v2/check-ins/extract status=200`.
- [x] Test an increment and mood: “I read 3 more pages today. I feel calm,
  eight out of ten.” Confirm the saved Check-In appears normally, progress
  increases by exactly 3, and mood becomes Calm, 8/10.
- [x] Test an absolute total and mood: “I’ve read 10 pages total today. I feel
  focused, seven out of ten.” Confirm today’s progress becomes exactly 10—not
  the previous total plus 10—and mood becomes Focused, 7/10.
- [x] Confirm the existing recording, processing, saved-row, transcript,
  success-highlight, and error UI remain unchanged.
- [x] After 6 PM local time, try an intentionally unclear update such as “I did
  6 pages.” If `Clarify Progress` appears, verify `Total today`, `6 more`, and
  `Skip`. This prompt is model-confidence-dependent and also requires a
  material change of at least 20% of the intention target.
- [x] Confirm successful extractions log `checkin_extract_ok` and applied clear
  updates log `checkin_applied`.
- [x] Do not enable `/v2/listening/extract` until the checks above pass.

### Listening Session physical test checklist

- [x] Install the current Debug build over the existing physical-iPhone app
  without deleting it, then start a Listening Session from Today.
- [x] Record a short clear session such as “I need to call Mom tomorrow at
  three PM. I also need to review my budget this week,” then end the session.
- [x] Confirm the existing active, stopping, processing, and ready UI states
  behave normally and the saved session transcript remains available.
- [x] Confirm the Xcode console shows
  `v2_request_start task=/v2/listening/extract` followed by
  `v2_response_received task=/v2/listening/extract status=200`.
- [x] Confirm queue order remains serial through `[extract] enqueued`,
  `[extract] started`, and `[extract] done`, with `extract_ok` reporting the
  resulting item count.
- [x] Confirm the extracted event/intention appears in Insights with its source
  quote and remains present after terminating and reopening Attune.
- [x] Record more than one segment to exercise the automatic segment boundary.
  Confirm each segment is transcribed and organized in index order, and the
  later segment can use the previous segment’s context without duplicate items.
- [x] Record a sparse session containing no clear intention, commitment, event,
  or meaningful state. Confirm zero extracted items is treated as a successful
  completed session rather than an error.
- [x] Lock the iPhone briefly during an active session, unlock it, finish the
  session, and confirm recording, transcription, extraction, and storage still
  complete.
- [x] Do not move Release/TestFlight to `/v2` until this checklist passes.

## Public pages and App Store setup

The detailed, ordered manual checklist is maintained in
`YOUR_REMAINING_STEPS.md`; keep these summary boxes synchronized with it.

- [ ] Add the private support/privacy email.
- [ ] Publish the prepared `/docs` website through GitHub Pages.
- [ ] Verify the landing, Privacy, Support, and Terms URLs.
- [ ] Enter the Privacy URL in App Store Connect.
- [ ] Complete the App Privacy answers in App Store Connect.
- [ ] Confirm `com.scottoliver.Pondera.Intentions.monthly` is $4.99/month with no introductory offer in App Store Connect.
- [ ] Create an approved checkpoint commit when the UI is accepted.
- [ ] Prepare and upload a TestFlight build with Scott's approval.
- [ ] Submit to the App Store only with Scott's approval.

## Marketing and Meta ad preparation

- [ ] Prepare a clean simulator dataset for screenshots and video.
- [ ] Capture polished vertical 9:16 footage of Today, Voice Check-In, Insights, and Momentum.
- [ ] Create an ad variant that links directly to the App Store.
- [ ] Create an ad variant that links to the landing page before the App Store.
- [ ] Add concise AI voiceover and burned-in captions.
- [ ] Test light AI animation or character overlays while keeping real app footage as the core.
- [ ] Prepare App Store screenshots and landing-page visuals using the same visual system.
- [ ] Test multiple hooks, including:
  - “Turn what you say into trackable momentum.”
  - “Notice the intentions you keep repeating.”
  - “See whether your daily goals are actually moving.”

## Future product idea — not assigned to a release phase

Allow the user to explicitly promote an intention discovered during a Listening Session into a quantitative tracked intention. This must require confirmation and must never happen automatically.

Speaker-aware Listening Sessions are also deferred and unassigned. The
planning-only feasibility, ownership, filtering, data, verification, and rollout
gates are documented in `SPEAKER_AWARE_LISTENING_BUILD_PLAN.md`. The recommended
v1 contract performs speaker analysis locally and sends only speech confidently
matched to the Attune user; it never identifies another speaker.

## Demo-data cleanup reminder

The current Debug simulator may contain removable Momentum demo data. Remove it through:

**Settings → Developer → Remove and Verify Demo Data**

The cleanup contract is documented in `Pondera/Pondera/Storage/MomentumDemoDataManager.swift`.
