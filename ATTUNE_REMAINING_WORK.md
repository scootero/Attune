# Attune Remaining Work

Last updated: August 5, 2026

This is the concise tracker for the work remaining after completion of UI Phases 0–6. The detailed history and verification log remain in `ATTUNE_UI_RELEASE_PLAN.md`.

## Current position

- Phases 0–6 are implemented at the UI level.
- The approved Free/Pro model is implemented: Free has one active intention,
  one Voice Check-In per day, today's Momentum only, and a free 6 PM reminder.
- Pro unlocks additional intentions, unlimited check-ins, Listening Sessions,
  Insights, Momentum history/Week/Month, voice intention setup, and export.
- Free Home and Momentum expose only today's progress; the weekly Home preview is Pro-only.
- The local StoreKit product is configured for $4.99/month with a three-day
  introductory trial. The same price and offer still must be created in App Store Connect.
- Momentum Day, Week, Month, and Progress History have been tested with removable simulator-only demo data.
- The production Cloudflare/OpenAI architecture and final provider-specific privacy wording require Scott's decision.
- Phase 7 is the next implementation phase after that decision.

## Phase 6 — Settings, onboarding, privacy, and paywall

- [x] Reorganize Settings into Membership, Notifications, Privacy & Data, and Support.
- [x] Show microphone, speech-recognition, and notification permission status with an iOS Settings entry point.
- [x] Replace the confusing export wording about “training purposes.”
- [x] Add a short, benefit-focused first-run onboarding flow.
- [ ] Clearly disclose AI processing and privacy without overwhelming the user.
- [x] Professionally brand the Attune Pro subscription/paywall screen.
- [x] Polish StoreKit unavailable, loading, and error states.
- [x] Polish About, Support, Privacy, Terms, and data-request entry points.

The final AI-disclosure checkbox stays open until the production API design is approved. The current app still sends transcript requests through the existing Cloudflare Worker to OpenAI; no API architecture was changed during Phase 6.

## Decisions needed before Phase 7

- [ ] Approve hardening the existing Cloudflare Worker as Attune's production AI gateway.
- [x] Free/Pro limits approved and implemented as described above.
- [ ] Approve final provider-specific privacy wording after the gateway design is settled.

## Phase 7 — Accessibility and release QA

- [ ] Audit VoiceOver labels and hints.
- [ ] Ensure statuses are understandable without relying only on color.
- [ ] Test Dynamic Type, contrast, Reduce Motion, and touch-target sizes.
- [ ] Check small and large iPhone layouts.
- [ ] Check iPad layouts.
- [ ] Test offline behavior and denied permissions.
- [ ] Test processing failure and recovery states.
- [ ] Test StoreKit failure and recovery states.
- [ ] Configure and verify the $4.99/month product and three-day free trial in App Store Connect/Sandbox.
- [ ] Complete final Debug and Release builds.
- [ ] Review App Store metadata, privacy disclosures, and legal/support links.

## Physical-device verification

These flows are implemented but cannot be completely proven in the iOS Simulator.

- [ ] Verify successful Voice Check-In transcription and saved-result UI.
- [ ] Verify successful Listening Session transcription.
- [ ] Test a real phone/audio interruption, background recovery, and continued processing.

## Public pages and App Store setup

- [ ] Add the private support/privacy email.
- [ ] Publish the prepared `/docs` website through GitHub Pages.
- [ ] Verify the landing, Privacy, Support, and Terms URLs.
- [ ] Enter the Privacy URL in App Store Connect.
- [ ] Complete the App Privacy answers in App Store Connect.
- [ ] Match `com.scottoliver.Attune.monthly` to $4.99/month with a three-day free-trial introductory offer in App Store Connect.
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

## Demo-data cleanup reminder

The current Debug simulator may contain removable Momentum demo data. Remove it through:

**Settings → Developer → Remove and Verify Demo Data**

The cleanup contract is documented in `Attune/Attune/Storage/MomentumDemoDataManager.swift`.
