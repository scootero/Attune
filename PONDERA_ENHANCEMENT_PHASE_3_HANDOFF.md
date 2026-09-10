# Attune Enhancement Phase 3 Handoff

Last updated: August 7, 2026

## Start here in the next Codex task

Phase 2 implementation and automated verification are complete in this working
tree. Preserve every existing change. Before Phase 3 work:

1. Run `git status --short` and do not stash, reset, delete, or overwrite any
   existing change.
2. Read this file completely.
3. Read the shared ground rules and **Enhancement Phase 3** in
   `CODEX_BUILD_PROMPTS.md`.
4. Confirm the physical-device Phase 2 gate below with the user. Do not begin
   Phase 3 design or implementation until the user says it passed.
5. Phase 3 has two mandatory design approvals: AI task routing/cost policy and
   additive progress provenance. Audit and report both proposals before editing
   Phase 3 code. Do not silently reuse the Check-In route, create a phantom
   CheckIn, or put a Session ID into a CheckIn ID field.

## Phase 2 result

Phase 2 adds a read-only Session Recap under the independent
`SessionRecapFeature.isEnabled` flag. The flag is on in DEBUG and off in RELEASE.

Implemented:

- Automatically presents a recap sheet after Home's existing processing check
  observes a completed Talk it out session.
- Shows the same recap again from the existing Session Detail path.
- Selects one headline in priority order: reliable recurring topic, corrected
  commitment count, then neutral capture count.
- Counts distinct parent sessions in the current calendar month using
  `Session.startedAt`; multiple items in one session count once.
- Uses only `ItemCorrection.isIncorrect` as recap exclusion. Legacy
  `reviewState == "rejected"` remains eligible.
- Skips recurring-topic claims when evidence is orphaned or a linked item has a
  title/category correction that makes frozen topic membership unreliable.
- Shows at most one deterministic corrected intention/commitment quote,
  normalizes whitespace, and truncates to at most 100 user-perceived characters
  on a word boundary.
- Preserves the existing Session Detail capture section and rows unchanged.
- Uses a dedicated topic snapshot decoder that does not call the migrating,
  repairing `TopicAggregateStore.loadTopics()` path.
- Adds an adaptive Session Detail metadata layout for Accessibility XXXL.

No model schema, store schema, extraction, transcription, recorder, progress,
or network behavior changed. No new persisted recap data exists.

## Phase 2 files

Added:

- `Pondera/Pondera/Understanding/SessionRecapBuilder.swift`
- `Pondera/Pondera/Storage/SessionRecapTopicSnapshotReader.swift`
- `Pondera/Pondera/UI/Library/SessionRecapView.swift`
- `Pondera/PonderaTests/SessionRecapBuilderTests.swift`
- `Pondera/PonderaTests/SessionRecapReadOnlyTests.swift`

Edited:

- `Pondera/Pondera/UI/Home/HomeRecordView.swift`
- `Pondera/Pondera/UI/Library/SessionDetailView.swift`

Revert Phase 2 by reverting those two edits and removing the five added files.
There is no data migration to reverse.

## Automated verification completed

- Full `xcodebuild test` on iPhone 17 Pro simulator: **TEST SUCCEEDED**.
- Final generic iOS Simulator Release build: **BUILD SUCCEEDED**.
- All existing tests and 11 focused recap/read-only tests passed.
- `git diff --check` passed.
- Static diff inspection confirmed no changes to `ExtractionQueue`,
  `ExtractorService`, `RecorderService`, `TranscriptionQueue`,
  `TranscriptionWorker`, or `ProgressCalculator`.
- The new recap source contains no save, write, move, repair, delete, directory
  creation, or store-update calls.
- Read-only tests verified legacy and malformed topic files were not migrated,
  renamed, repaired, rewritten, resized, or given new creation/modification
  timestamps.
- A simulator integration pass compared all non-log stored files before and
  after reopening a recap. File list, bytes, size, access time, modification
  time, metadata-change time, and creation time were identical.
- Simulator UI verified a recurring-topic headline, quote, unchanged capture
  row, transcript, accessibility tree, standard layout, and Accessibility XXXL.
- Simulator transition testing verified Home's existing timer moved from
  “Organizing what you said…” to the recap sheet when a session changed from
  processing to complete, without modifying `ExtractionQueue`.

Evidence:

- `/Users/scott/.codex/visualizations/2026/08/07/019fda33-de35-7e51-abd3-b6c55c1d052d/phase2/recap-standard.png`
- `/Users/scott/.codex/visualizations/2026/08/07/019fda33-de35-7e51-abd3-b6c55c1d052d/phase2/recap-axxxl.png`

The simulator-only session/topic fixtures used for UI verification were removed
after testing.

## Physical-device Phase 2 gate

Use a Debug build, because `SessionRecapFeature` remains Release-off.

1. **First/new topic:** Finish a Talk it out session about a topic that has not
   appeared earlier this month. Confirm the recap appears automatically after
   processing and uses the corrected commitment headline when applicable,
   otherwise the neutral count. Confirm it is also reachable from Past sessions.
2. **Recurring topic:** Earlier in the same calendar month, create one completed
   session about a clear topic. Create another session about that same topic.
   Confirm the newer recap says `You mentioned {topic} across 2 sessions this
   month.` Multiple captures in either session must not increase that session
   count.
3. **All captures incorrect:** Open every capture from a completed session, tap
   Review, enable Hide from Insights, and return to the session. Confirm the
   recap says `Nothing new was captured.`, shows no quote, and shows no capture
   rows.
4. Confirm the capture rows, links, and transcript behave exactly as before.
5. With large text and VoiceOver, confirm the recap headline and optional quote
   are readable as one recap element and the screen remains vertically
   scrollable.

If any item fails, fix Phase 2 and repeat that item. After all five pass, report
that `SessionRecapFeature.isEnabled` is eligible for Release graduation and wait
for explicit approval before changing its Release value.

## Phase 3 boundary

Phase 3 must begin with a report, not code. The report must cover:

- Whether progress candidates can be derived defensibly without a new AI call.
- If not, the proposed server-owned task/route, payload, usage controls, retry
  behavior, billing/auth failure behavior, and Release fallback.
- Deterministic candidate validation and ranking, capped at three suggestions.
- A new additive accepted/dismissed outcome store keyed by stable candidate ID.
- The smallest backward-compatible provenance change required because
  `ProgressEntry.sourceCheckInId` currently assumes a real CheckIn.
- Every reader/adapter affected by that provenance change.
- How duplicate activity mentioned in both Check-In and Talk it out avoids
  surprising double-counting.

No Phase 3 implementation begins until the user explicitly approves both the AI
routing proposal and provenance proposal.
