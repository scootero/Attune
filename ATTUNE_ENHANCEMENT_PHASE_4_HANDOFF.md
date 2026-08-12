# Attune Enhancement Phase 4 Handoff

Status: implemented behind `IntentionSuggestionFeature.isEnabled` (Debug on,
Release off). The additive Worker route was deployed on August 12, 2026 as
version `9c8c4fb2-e261-4340-a69d-bbab4b05d09f` and passed an authenticated,
synthetic learning-theme smoke test with HTTP 200 and contract version 1. It
returned `Teach one idea from memory`, confirming specialized learning routing.

## Product behavior

- Recurring-topic qualification is deterministic and read-only over existing
  topic, extraction, correction, session, and intention data.
- Every completed Talk it out session posts an in-process completion event and
  immediately reevaluates eligibility without modifying the extraction queue.
- Every install gets a Phase 4 introduction clock: days 0-20 require two
  distinct sessions and allow one suggestion every four days; days 21-50
  require three sessions and allow one weekly; steady state requires four
  sessions spanning 14 days and allows one every 14 days.
- Only `ItemCorrection.isIncorrect` excludes evidence. A legacy rejected item
  remains eligible. Orphaned evidence and title/category corrections skip the
  stored topic grouping conservatively.
- Distinct sessions are counted by parent session ID and assigned to months by
  `Session.startedAt`.
- The Worker may select exactly one action from its curated low-risk catalog or
  return no suggestion. Sensitive or individualized contexts are instructed to
  return none.
- The catalog includes small movement, spending-awareness, retrieval-practice,
  concrete-next-step, planning, and relationship check-in actions. Selection
  prefers learning, noticing, practicing, or making a concrete move instead of
  simply repeating the topic.
- The Home card offers `Why this?`, `Not for me`, and `Add this`. Add opens the
  existing intention editor with all fields visible and editable. Nothing is
  saved until the user taps the normal Save control.
- Declining permanently blocks that exact action ID and pauses its topic for 90
  days. One outstanding suggestion and global cooldowns prevent stacking.
- When the user's tier is full, the card recommends the first zero-progress
  intention in display order, otherwise the lowest three-day average. Review
  Swap opens the normal editor with that removal and the new action staged; the
  saved IntentionSet changes only after the normal Save tap.

## One Thing Mode

- `OneThingModeFeature` is Debug on and Release off.
- On launch, two previous complete local-calendar days with no ProgressEntry or
  manual override activate a reversible presentation mode when at least two
  intentions exist.
- The first/top intention is focused; all others remain in the active
  IntentionSet, retain history, and appear muted. The user can switch focus or
  exit. Exiting requires two new complete quiet days before reactivation.
- State is additive in `Documents/Attune/OneThingMode.json`. No intention,
  progress, Check-In, extraction, or Momentum schema is changed.

## Persistence and boundaries

The new on-device files are `Documents/Attune/IntentionSuggestions.json` and
`Documents/Attune/OneThingMode.json`. They store suggestion cadence/outcomes
and reversible UI focus state. Existing schemas and the recording, transcription,
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
9. With two or more intentions, leave the previous two complete days without a
   progress entry or manual override. Launch after midnight and verify One Thing
   Mode focuses the top intention, lets you switch, and leaves muted intentions
   and their history intact. Exit it and verify it does not immediately return.

## Revert

Set `IntentionSuggestionFeature.isEnabled` to false for Debug or revert the
Phase 4 files/edits. Release is already off. Removing the Worker route is
independent. The additive JSON file can remain harmlessly unread.

## Next phase

Return to the approved Phase 3 routing/provenance design only after Phase 4 has
passed physical-device verification. Phase 4 has no dependency on the Phase 3
`ProgressEntry` provenance change.
