# ATTUNE V1 BACKBONE — HANDOFF / CONTEXT PACK (UPDATED)
# (Copy/paste into a new chat or share with another AI)

## Current status (where we are right now)
- Completed through:
  - Slice 1: App shell + tabs + Home UI scaffold
  - Slice 2: Session/Segment models + JSON persistence (Codable)
  - Slice 3: AVAudioRecorder segmented recording (60s segments) + background recording capability (audio background mode) + persisted metadata
  - Slice 4: TranscriptionQueue + TranscriptionWorker using SpeechAnalyzer + SpeechTranscriber for CLOSED segment files; delete audio on success; keep audio on failure
  - Slice 5: Stop behavior + drain queue to finalize session transcript (intended)
  - Slice 6: Recovery on launch for incomplete sessions/segments
  - Slice 6.5: Structured console logging via Logging/AppLogger.swift (prefix format; transcript preview only)
- Current observed bug:
  - Session can remain stuck in status=processing after transcription completes and queue is empty (Home button stays disabled/spinner; Library shows processing).
  - Root cause likely missing “finalize session to complete when no queued/transcribing segments remain” logic and/or queue running flags not resetting.

## v1 goal (this version)
Reliable backbone that can:
- Record long periods, including phone locked/backgrounded
- Segment audio (default 60s for debugging; change to 300s later)
- Queue and transcribe segments in order
- Persist sessions/segments/transcripts locally (JSON)
- Delete audio after successful transcript persistence
- Recover and resume after suspension/termination
- Provide Library “debug cockpit” to validate everything easily
- Swift 5 only (avoid Swift 6-only patterns)

## Engines / APIs chosen
- Recording: AVAudioRecorder (record-to-file)
- Transcription: iOS 26+ SpeechAnalyzer + SpeechTranscriber (file-based per closed segment)

## Project structure (already created)
Attune/
  App/
    AttuneApp.swift
    ContentView.swift
    RootTabView.swift
  Models/
    Session.swift
    Segment.swift
  Storage/
    AppPaths.swift
    SessionStore.swift
  Audio/
    RecorderService.swift
    TranscriptionQueue.swift
    TranscriptionWorker.swift
  UI/
    Home/
      HomeRecordView.swift
    Library/
      LibraryView.swift
      SessionListView.swift
      SegmentListView.swift
      SessionDetailView.swift
      SegmentDetailView.swift
  Logging/
    AppLogger.swift

## Data model (Codable, persisted as JSON)
Session (minimum)
- id (UUID string)
- startedAt, endedAt?
- status: recording | stopping | processing | complete | error
- segmentDurationSec (default 60 now)
- segments: [Segment]
- lastError?

Segment (minimum)
- id (UUID string)
- sessionId
- index (Int)
- startedAt, endedAt?
- audioFileName (e.g., segment_001.m4a)
- status: writing | queued | transcribing | done | failed
- transcriptText?
- error?
- audioDeletedAt?

## Storage locations
- Base: Documents/Attune/
- Sessions JSON: Documents/Attune/Sessions/<sessionId>.json
- Audio per session: Documents/Attune/Audio/<sessionId>/segment_XXX.m4a

## Intended flow (canonical)
1) Start Recording
- Create Session immediately (status=recording) and persist
- Start segment_001.m4a
- Timers:
  - 1s elapsed timer
  - rotation every segmentDurationSec: stop recorder, finalize segment metadata, enqueue, start next

2) Segment rotation
- Stop recorder -> file finalized
- Segment endedAt, status queued, persist
- Enqueue segment to TranscriptionQueue
- Start next segment recorder

3) TranscriptionQueue (serial FIFO)
- Mark segment transcribing -> persist
- Transcribe closed file using SpeechAnalyzer + SpeechTranscriber
- Success: transcriptText set, status done, persist; delete audio; set audioDeletedAt; persist
- Failure: status failed, error set, persist; keep audio for retry

4) Stop Recording
- Stop current segment -> enqueue
- Mark session status processing + endedAt -> persist
- Drain transcription for that session
- Build full transcript by concatenating segment transcripts by index
- Mark session complete -> persist

5) Recovery on launch
- For sessions in recording/stopping/processing:
  - transcribing -> queued
  - queued/failed segments with audio present and no transcript -> eligible
- enqueue eligible segments; resume worker

## Logging (Xcode console)
- Prefixes: <REC> <SEG> <FILE> <QUE> <TSCR> <STORE> <ERR>
- Always include session shortId + seg index + file where relevant
- Log only transcript preview (first ~8 words), never full transcript

## Known issue and required fix
- Fix required: ensure session transitions processing -> complete when the last segment finishes (and queue flags reset).
- Add log when session marked complete:
  <STORE> ... Session saved session=<short> status=complete
  and optionally:
  <QUE> ... Drain complete session=<short>

## UI v1 target (“debug cockpit”)
Home:
- Title “Attune”
- Record button (red circle) / Stop (square)
- Duration mm:ss
- Segment counter
- Show Processing state only while session is truly processing

Library:
- Top segmented control: Sessions | Segments
- Sessions list: status, duration, segment count
- Segments list: session shortId, segment index, status, transcript exists
- Session detail: list segments + metadata + full joined transcript
- Segment detail: transcript + metadata + audio present? + error

## Constraints for Cursor (avoid chaos)
- Swift 5 only
- Minimal diffs, no refactors unless required
- No new files unless explicitly allowed in the slice
- Single @main entry point remains AttuneApp (no alternate app shells)
