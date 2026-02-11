# Segment State Synchronization Bug - Fixes Applied

## Problem Summary

Segments were being transcribed successfully but showing "failed" status in the UI. The root cause was a state synchronization bug where:

1. **Segments 0 & 1 transcribed successfully** and were saved with `status=done`
2. **Recovery/resume logic re-enqueued them** after recording stopped
3. **This caused UI state desync** - showing "failed" when actually "done"

## Root Causes Identified

1. **Recovery logic was not idempotent** - re-enqueued segments that already had transcripts
2. **Session status oscillated** between "recording" and "processing" after stop, triggering recovery
3. **UI badge mapping** didn't properly distinguish between segment statuses

## Fixes Applied

### Fix 1: Idempotent Recovery Logic ✅

**Files Modified:**
- `Attune/Attune/Audio/TranscriptionQueue.swift`
- `Attune/Attune/Storage/SessionStore.swift`

**Changes:**

#### TranscriptionQueue.enqueueAllEligibleSegmentsOnLaunch()
- ✅ **NEVER enqueue segments with `status="done"`** (already completed)
- ✅ **Check if transcript exists** before enqueueing
- ✅ **Force status to "done"** if transcript exists but status is stale
- ✅ **Added defensive logging** for recovery decisions
- ✅ **Track skip counts** (skipped_done, skipped_has_transcript)

**Logic:**
```swift
// NEVER enqueue if status=done
if segment.status == "done" { skip }

// NEVER enqueue if transcript exists (force to done)
if hasTranscript { 
    force status = "done"
    skip 
}

// Only enqueue if: status in {queued, transcribing, failed} 
// AND no transcript AND audio exists
```

#### SessionStore.recoverIncompleteSessionsOnLaunch()
- ✅ **Check for transcripts** before resetting "transcribing" segments
- ✅ **Force to "done"** if segment has transcript (fixes state desync)
- ✅ **Only reset to "queued"** if no transcript exists (actual interruption)

**Logic:**
```swift
if segment.status == "transcribing" {
    if hasTranscript {
        // Already completed - fix state
        segment.status = "done"
    } else {
        // Actually interrupted - retry
        segment.status = "queued"
    }
}
```

### Fix 2: Decouple "No Speech" from "Failed" ✅

**Files Modified:**
- `Attune/Attune/UI/Library/SessionListView.swift` (StatusBadge)
- `Attune/Attune/Audio/TranscriptionQueue.swift` (logging)

**Changes:**

#### StatusBadge UI Component
- ✅ **Show green "done" badge** for `status="done"` (regardless of reason)
- ✅ **Show red "failed" badge** ONLY for `status="failed"`
- ✅ **Added status mappings** for all segment states (writing, queued, transcribing, done, failed)

**Badge Colors:**
```swift
"done" → green (always, even if reason=no_speech)
"failed" → red (only for actual failures)
"queued" → blue
"transcribing" → blue
"writing" → orange
```

#### Transcription Error Logging
- ✅ **Changed "no speech" from `<ERR>` to `<TSCR>`** log tag
- ✅ **Clarified that silence is expected**, not an error

### Fix 3: Hard Transition on Stop ✅

**Files Modified:**
- `Attune/Attune/Audio/RecorderService.swift`

**Changes:**

#### stopRecording()
- ✅ **Set `session.status = "processing"` ONCE**
- ✅ **Clear `currentSession` immediately** after save (prevents stale saves)
- ✅ **Added logging** to confirm hard transition
- ✅ **Never save with `status="recording"` after stop**

#### handleInterruptionBegan()
- ✅ **Same hard transition logic** for interruptions
- ✅ **Set `status="processing"` ONCE** if valid segments exist
- ✅ **Added logging** to confirm transition

**Logic:**
```swift
// Hard transition - never revert
session.status = "processing"
try SessionStore.shared.saveSession(session)

// Clear to prevent stale saves
currentSession = nil
```

## Additional Improvements

### Defensive Logging
- ✅ **Added `[RECOVERY]` log prefix** for recovery operations
- ✅ **Log segment decisions** (enqueue/skip with reasons)
- ✅ **Track metrics** (enqueued count, skip counts)
- ✅ **Added ✅ emoji** for successful state transitions (easier to spot in logs)

### Debug Function Safety
- ✅ **Updated `resumeQueuedSegments()`** with safety note
- ✅ **Documented that enqueue() is now idempotent**

## Testing Checklist

### Scenario 1: Normal Recording
- [ ] Start recording
- [ ] Wait for 5+ minutes (multiple segments)
- [ ] Stop recording
- [ ] Verify all segments show "done" status (not "failed")
- [ ] Verify transcripts are present

### Scenario 2: Recovery After App Restart
- [ ] Start recording
- [ ] Wait for 5+ minutes (multiple segments)
- [ ] Force quit app (simulate crash)
- [ ] Restart app
- [ ] Verify recovery enqueues only segments without transcripts
- [ ] Verify segments with transcripts are forced to "done"
- [ ] Check logs for `[RECOVERY]` entries

### Scenario 3: Debug Resume Button
- [ ] Open session with completed segments
- [ ] Tap "Resume queued" debug button
- [ ] Verify segments with transcripts are NOT re-enqueued
- [ ] Verify only truly queued segments are enqueued
- [ ] Check logs for skip messages

### Scenario 4: Silent Segments
- [ ] Record with periods of silence
- [ ] Verify silent segments show "done" status (green badge)
- [ ] Verify no `<ERR>` logs for "no speech detected"
- [ ] Verify `<TSCR>` logs show "no speech" as expected

## Expected Log Patterns (After Fix)

### Good Recovery Log:
```
<QUE> [RECOVERY] Segment 0: status=done, decision=skip
<QUE> [RECOVERY] Segment 1: status=done, decision=skip
<QUE> [RECOVERY] Segment 2: status=queued, transcript=empty, audio=exists, decision=enqueue
<QUE> [RECOVERY] complete enqueued=1 skipped_done=2 skipped_has_transcript=0
```

### Good Stop Transition Log:
```
<REC> Recording stop requested session=371079
✅ Session 371079 transitioned to status=processing (final)
<STORE> Session saved session=371079 status=processing
```

### Good "No Speech" Log:
```
<TSCR> Transcription done (no speech) session=371079 seg=3
<STORE> Segment saved session=371079 seg=3 status=done transcriptChars=0 reason=no_speech
```

## Additional Changes

### Segment Duration Configuration
- ✅ **Added constant `segmentDurationSeconds`** in `RecorderService` (180 seconds = 3 minutes)
- ✅ **Centralized configuration** - single source of truth for segment duration
- ✅ **Updated all references** to use the constant:
  - Session metadata (`segmentDurationSec`)
  - Rotation timer interval
  - Documentation comments

**Rationale:** 3-minute segments provide:
- Faster feedback loop for testing transcription issues
- Sufficient context for GPT-4o-mini extraction (200-400 words typical)
- More data points per recording session
- Easier to spot state synchronization bugs

## Files Modified

1. `Attune/Attune/Audio/TranscriptionQueue.swift` - Idempotent recovery + logging
2. `Attune/Attune/Storage/SessionStore.swift` - Idempotent recovery
3. `Attune/Attune/Audio/RecorderService.swift` - Hard stop transition + segment duration constant
4. `Attune/Attune/UI/Library/SessionListView.swift` - StatusBadge UI fix
5. `Attune/Attune/UI/Library/SessionDetailView.swift` - Debug function docs

## Commit Message

```
Fix segment state synchronization bug

Root cause: Recovery logic was re-enqueueing segments that already had
transcripts, causing UI to show "failed" when segments were actually "done".

Fixes:
1. Made recovery logic idempotent - never enqueue segments with transcripts
2. Updated UI to show correct badge colors for segment status
3. Ensured session.status transitions to "processing" once (never reverts)

- TranscriptionQueue: Skip segments with status=done or existing transcripts
- SessionStore: Force segments with transcripts to status=done during recovery
- RecorderService: Hard transition to status=processing on stop (no revert)
- StatusBadge: Show green for "done", red only for "failed"
- Logging: Added [RECOVERY] prefix and defensive logging for debugging

Result: Segments now display correct status in UI, recovery is safe and
idempotent, and "no speech detected" is treated as expected (not error).
```

## Notes

- **All fixes are backward compatible** - no data migration needed
- **Recovery logic will auto-fix** any existing sessions with stale state
- **Defensive logging** makes future debugging easier
- **No performance impact** - checks are lightweight
