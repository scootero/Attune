# Attune Enhancement Phase 2 Handoff

Last updated: August 7, 2026

## Start here in the next Codex task

Phase 1 implementation is complete in this working tree. Do not discard, stash,
or overwrite the existing changes. Before doing anything else:

1. Run `git status --short` and preserve every existing change.
2. Read this file completely.
3. Read the shared ground rules and **Enhancement Phase 2** in
   `CODEX_BUILD_PROMPTS.md`.
4. Confirm the physical-device Phase 1 gate below with the user. Do not begin
   Phase 2 implementation until the user says it passed.
5. Once the gate passes, audit the Phase 2 assumptions and report discrepancies
   before editing. Phase 2 must remain read-only over existing stored data and
   must use the independent `SessionRecapFeature.isEnabled` flag (DEBUG on,
   RELEASE off).

## Phase 1 result

Phase 1 changed only user-facing copy, reminder copy, and layout. It did not
change recording, transcription, extraction, progress behavior, persisted model
schemas, or on-disk stores.

Implemented:

- Renamed user-facing Listening Session language contextually to **Talk it out**.
- The visible tab label is **Talk** and its accessibility label is
  **Talk it out**.
- Added the approved vocabulary: **Start talking**, **You're talking it out**,
  **Finish**, and **Past sessions**.
- Replaced the guilt/percentage reminder with:
  - Title: `A quick check-in`
  - Body: `Anything you'd like to log today?`
- Added `Track what matters. Talk out the rest.` to the first onboarding page.
  No artificial splash or launch delay was added.
- Geometrically centered the Home wordmark with symmetric 44-point control
  slots while preserving the Settings button.
- Added the three static Talk it out occasion examples. They are explanatory
  text only and have no extraction behavior.
- Voice Check-In terminology was intentionally left alone.

There is no Phase 1 feature flag: these are approved copy/layout changes. Revert
by reverting the Phase 1 files listed below; there is no data migration.

## Files changed for Phase 1

App behavior and UI:

- `Pondera/Pondera/App/DailyReminderNotificationService.swift`
- `Pondera/Pondera/App/RootTabView.swift`
- `Pondera/Pondera/UI/AIPrivacyDisclosureSheet.swift`
- `Pondera/Pondera/UI/Calendar/PonderaCalendarView.swift`
- `Pondera/Pondera/UI/Home/HomeRecordView.swift`
- `Pondera/Pondera/UI/Home/HomeView.swift`
- `Pondera/Pondera/UI/Library/InsightsListView.swift`
- `Pondera/Pondera/UI/Library/LibraryView.swift`
- `Pondera/Pondera/UI/Library/SessionDetailView.swift`
- `Pondera/Pondera/UI/Library/SessionListView.swift`
- `Pondera/Pondera/UI/Library/TopicsListView.swift`
- `Pondera/Pondera/UI/OnboardingView.swift`
- `Pondera/Pondera/UI/Settings/AboutView.swift`
- `Pondera/Pondera/UI/Settings/PaywallView.swift`
- `Pondera/Pondera/UI/Settings/PrivacyDataView.swift`
- `Pondera/Pondera/UI/Settings/SettingsView.swift`

Tests/project metadata:

- Added `Pondera/PonderaTests/DailyReminderCopyTests.swift`.
- `Pondera/Pondera.xcodeproj/project.pbxproj` was updated by Xcode while adding and
  discovering the test. Its diff adds the test-target dependency metadata and
  reformats two runpath arrays; inspect it before any further project-file edit.
- `CODEX_BUILD_PROMPTS.md` is the untracked controlling enhancement plan supplied
  by the user. Preserve it.

## Verification already completed

- `xcodebuild test` on an iPhone 17 Pro simulator: **TEST SUCCEEDED**.
- Release build for generic iOS Simulator: **BUILD SUCCEEDED**.
- The new reminder-copy test verifies the exact approved title/body and guards
  against percentages, guilt copy, or quoted user content.
- Simulator visual QA at standard size and Accessibility XXXL:
  - The Home wordmark remains centered without colliding with Settings.
  - The visible tab label renders as **Talk**.
  - Talk it out content remains horizontally intact and vertically scrollable.
  - Onboarding tagline renders cleanly.
- Accessibility inspection confirmed the Talk it out screen heading, occasion
  examples, Start talking control and hint, and Past sessions control.

Evidence:

- `.../phase1/onboarding-standard.png`
- `.../phase1/onboarding-axxxl.png`
- `.../phase1/home-axxxl.png`
- `.../phase1/talk-standard.png`
- `.../phase1/talk-axxxl.png`

The full evidence directory is:
`/Users/scott/.codex/visualizations/2026/08/07/019fda33-de35-7e51-abd3-b6c55c1d052d/phase1`

## Physical-device gate still required

Codex could not verify local-notification delivery or actual VoiceOver speech on
a physical iPhone. Before Phase 2, the user must confirm all of the following:

1. Enable the daily reminder, set it a few minutes ahead, background/lock the
   phone, and confirm it arrives with title **A quick check-in** and body
   **Anything you'd like to log today?**
2. At the largest Dynamic Type size, confirm the tab shows **Talk** without
   clipping and the centered **Attune** wordmark does not collide with Settings.
3. With VoiceOver enabled, focus the Talk tab and confirm it is announced as
   **Talk it out**.

If any item fails, fix Phase 1 and repeat that item before starting Phase 2.

## Phase 2 boundary

Phase 2 is the Session Recap described in `CODEX_BUILD_PROMPTS.md`. The first
step is an audit, not implementation. Verify the current types, corrections
overlay semantics, session/topic relationships, and extraction-completion UI
before proposing edits.

Key constraints to retain:

- Read-only over existing stored data; write nothing new to disk.
- Never modify `ExtractionQueue`, `ExtractorService`, or the transcription chain.
- Derive only literally true recap headlines from corrected effective items.
- Recurring-topic counts must use distinct parent sessions in the current
  calendar month, based on `Session.startedAt`, never lifetime occurrence count.
- Show at most one eligible, deterministic, normalized and truncated quote
  inside the recap, never in a notification.
- Exclude captures marked incorrect from every count, headline, topic-evidence,
  and quote decision.
- The recap must handle zero, one, and all-incorrect captures and remain
  reachable later from Session Detail.
- Add fixed-fixture unit tests for every headline branch and quote-selection
  rule, with no network.
- `SessionRecapFeature.isEnabled` must be DEBUG on and RELEASE off until physical
  verification and explicit Release approval.

Phase 2 is complete only after physical-device sessions cover: a first-ever
session, a session repeating an earlier topic, and a session whose captures are
all marked incorrect.
