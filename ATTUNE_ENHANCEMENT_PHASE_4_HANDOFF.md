# Attune Enhancement Phase 4 Handoff

Status: implemented behind `IntentionSuggestionFeature.isEnabled` (Debug on,
Release off). The additive Worker route was deployed on August 12, 2026 as
version `a897f40b-59fd-4e76-8bee-825f3da7cfde` and passed an authenticated,
synthetic smoke test with HTTP 200 and contract version 1.

## Product behavior

- Recurring-topic qualification is deterministic and read-only over existing
  topic, extraction, correction, session, and intention data.
- New users have evaluation opportunities on day 3 and day 10. Fewer than three
  completed sessions produces a restrained record-more nudge. Ramp cadence is
  weekly; steady-state cadence is every 14 days with four distinct sessions
  spanning at least 14 days.
- Existing installs enter steady state rather than replaying onboarding.
- Only `ItemCorrection.isIncorrect` excludes evidence. A legacy rejected item
  remains eligible. Orphaned evidence and title/category corrections skip the
  stored topic grouping conservatively.
- Distinct sessions are counted by parent session ID and assigned to months by
  `Session.startedAt`.
- The Worker may select exactly one action from its curated low-risk catalog or
  return no suggestion. Sensitive or individualized contexts are instructed to
  return none.
- The Home card offers `Why this?`, `Not for me`, and `Add this`. Add opens the
  existing intention editor with all fields visible and editable. Nothing is
  saved until the user taps the normal Save control.
- Declining permanently blocks that exact action ID and pauses its topic for 90
  days. One outstanding suggestion and global cooldowns prevent stacking.

## Persistence and boundaries

The only new on-device file is `Documents/Attune/IntentionSuggestions.json`.
It stores cohort/cadence state, the outstanding suggestion, and accepted or
declined outcomes. Existing schemas and the recording, transcription,
extraction, Check-In, progress, Momentum, and Phase 3 paths are unchanged.

## Physical verification

1. Install a Debug build on an iPhone.
2. Confirm onboarding and Talk it out explain that repeated themes may become a
   small editable step and that nothing is added automatically.
3. With qualifying repeated evidence, open Home and verify one card appears.
4. Open `Why this?`; verify quotes and dates belong to distinct sessions.
5. Tap `Add this`; change a field, cancel, and verify no intention was created.
6. Tap `Add this` again and Save; verify the normal intention appears and no
   progress entry was created.
7. For another suggestion tap `Not for me`; relaunch and verify it does not
   return. Confirm no second card stacks while one is outstanding.
8. Exercise a sensitive/medical transcript only with non-private test wording;
   verify the service returns no suggestion.

## Revert

Set `IntentionSuggestionFeature.isEnabled` to false for Debug or revert the
Phase 4 files/edits. Release is already off. Removing the Worker route is
independent. The additive JSON file can remain harmlessly unread.

## Next phase

Return to the approved Phase 3 routing/provenance design only after Phase 4 has
passed physical-device verification. Phase 4 has no dependency on the Phase 3
`ProgressEntry` provenance change.
