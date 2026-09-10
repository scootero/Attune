# Attune Enhancement Phase 4 Handoff

Status: the fully custom suggestion revision is implemented locally behind
`IntentionSuggestionFeature.isEnabled` (Debug on, Release off). It has not been
deployed to Cloudflare or installed on a physical iPhone. The August 12 Worker
deployment still uses the retired fixed-action contract; deploy and smoke-test
the Worker before testing this app revision on-device.

## Product behavior

- Recurring-topic qualification is deterministic and read-only over existing
  topic, extraction, correction, session, and intention data.
- Every completed Talk it out session posts an in-process completion event and
  immediately reevaluates eligibility without modifying the extraction queue.
- Every install gets a Phase 4 introduction clock: days 0-20 require two
  distinct sessions and allow one suggestion every three days. After day 20,
  three distinct sessions spanning at least three days are required, with a
  four-day cooldown.
- Only `ItemCorrection.isIncorrect` excludes evidence. A legacy rejected item
  remains eligible. Orphaned evidence and title/category corrections skip the
  stored topic grouping conservatively.
- Distinct sessions are counted by parent session ID and assigned to months by
  `Session.startedAt`.
- The retired 11-action catalog has been removed. The Worker asks the model for
  one fully custom, measurable micro-intention or no suggestion.
- The request includes corrected recurring evidence, active intention titles,
  aliases, targets, units and cadence, recent progress-day counts, and up to 100
  prior suggestion outcomes. It does not send confidence scores.
- The Worker independently validates title length, target bounds, supported
  units, daily/weekly cadence, normalized behavior fingerprint, evidence IDs,
  active-intention duplication, declined/recent repetition, and sensitive
  contexts. It supplies fixed safety notes and never accepts model-invented
  citations.
- The Home card offers `Why this?`, `Not for me`, and `Add this`. Add opens the
  existing intention editor with all fields visible and editable. Nothing is
  saved until the user taps the normal Save control.
- Declining permanently blocks the exact behavior fingerprint and close title
  rewrites. It does not ban the entire topic, so a meaningfully different idea
  may be considered after the normal cooldown. Accepted fingerprints are held
  out for 60 days to preserve variety.
- Fragmented topic aggregates can qualify together only when they share a
  category and a distinctive normalized term in their titles or evidence;
  distinct-session counting remains conservative.
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

The on-device files remain `Documents/Attune/IntentionSuggestions.json` and
`Documents/Attune/OneThingMode.json`. Suggestion actions and history gained
optional fingerprint, family, and title fields; older JSON still decodes.
Existing intention, extraction, progress, Momentum, and Phase 3 schemas and
pipelines are unchanged.

## Physical verification

### Rapid Debug test mode

`RapidIntentionSuggestionTestingFeature.isEnabled` is on only in Debug and off
in Release. It is an evaluation shortcut, not production cadence:

- Three eligible related mentions qualify when their trustworthy evidence
  timestamps are at least three minutes apart. They may come from three
  sessions or from separately timestamped segments in one session.
- Multiple extracted items from one segment do not create extra timed mentions.
  A normal Talk it out segment lasts five minutes, so a one-session test must
  run long enough to create three segments and finish processing them.
- It bypasses the first-20-days/session thresholds, date-span requirement,
  generation-attempt throttle, and suggestion cooldown. It does not bypass an
  already-outstanding suggestion, incorrect-item filtering, active-intention
  duplicate checks, permanent decline suppression, evidence validation, or
  medical/financial/crisis safety rules.
- Qualification forces an AI evaluation, not an unsafe or duplicate result. If
  the Worker returns no safe new action, Home shows a Debug diagnostic instead
  of inventing one. This distinction keeps the test representative of the real
  product.
- The app sends `rapidTestMode: true` to the server-owned Worker contract so the
  model prefers a safe supported suggestion when one exists. The matching
  Worker revision must be deployed before on-device testing.

To disable the shortcut, make
`RapidIntentionSuggestionTestingFeature.isEnabled` return `false` in Debug. No
stored data or migration needs to be reversed.

1. Deploy the matching Worker revision, then run an authenticated synthetic
   smoke test. The new app request is not compatible with the older deployed
   catalog validator.
2. Install a Debug build on an iPhone.
3. Confirm onboarding and Talk it out explain that repeated themes may become a
   small editable step and that nothing is added automatically.
4. During days 0-20, complete two related sessions and verify evaluation after
   processing. After day 20, use three related sessions spanning three days.
5. Open `Why this?`; verify quotes and dates belong to distinct sessions.
6. Tap `Add this`; change a field, cancel, and verify no intention was created.
7. Tap `Add this` again and Save; verify the normal intention appears and no
   progress entry was created.
8. For another suggestion tap `Not for me`; after the next qualifying cooldown,
   verify the exact behavior and a close rewrite do not return, while a truly
   different action for that topic remains possible.
9. Exercise a sensitive/medical transcript only with non-private test wording;
   verify the service returns no suggestion.
10. With two or more intentions, leave the previous two complete days without a
   progress entry or manual override. Launch after midnight and verify One Thing
   Mode focuses the top intention, lets you switch, and leaves muted intentions
   and their history intact. Exit it and verify it does not immediately return.

## Revert

Set `IntentionSuggestionFeature.isEnabled` to false for Debug or revert the
custom-contract files. Release is already off. Roll the Worker back to its
previous deployment independently. The additive optional JSON fields remain
harmless to older builds.

## Next phase

Return to the approved Phase 3 routing/provenance design only after Phase 4 has
passed physical-device verification. Phase 4 has no dependency on the Phase 3
`ProgressEntry` provenance change.
