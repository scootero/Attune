//
//  TranscriptionQueue.swift
//  Attune
//
//  Manages a FIFO queue of segments awaiting transcription.
//  Processes one segment at a time serially, using TranscriptionWorker to transcribe.
//  Updates segment status and persists results via SessionStore.
//

import Foundation
import Combine

/// Work item representing a segment to be transcribed
struct TranscriptionWorkItem: Equatable {
    let sessionId: String
    let segmentId: String
}

/// Manages the transcription queue and processes segments serially.
/// Automatically starts processing when segments are enqueued.
@MainActor
class TranscriptionQueue: ObservableObject {
    
    // MARK: - Published State
    
    /// Number of segments pending transcription
    @Published var pendingCount: Int = 0
    
    /// Whether the queue is currently processing a segment
    @Published var isRunning: Bool = false
    
    // MARK: - Singleton
    
    static let shared = TranscriptionQueue()
    
    // MARK: - Private State
    
    /// FIFO queue of work items
    private var queue: [TranscriptionWorkItem] = []
    
    /// Worker that performs actual transcription
    private let worker = TranscriptionWorker()
    
    /// Current processing task (to prevent duplicate processing)
    private var processingTask: Task<Void, Never>?
    
    private init() {}
    
    // MARK: - Public API
    
    /// Enqueues a single segment for transcription.
    /// Automatically starts processing if not already running.
    /// - Parameters:
    ///   - sessionId: The ID of the session containing the segment
    ///   - segmentId: The ID of the segment to transcribe
    func enqueue(sessionId: String, segmentId: String) {
        let workItem = TranscriptionWorkItem(sessionId: sessionId, segmentId: segmentId)
        
        // Avoid duplicate enqueue
        guard !queue.contains(workItem) else {
            print("[TranscriptionQueue] Segment \(segmentId) already in queue")
            return
        }
        
        // Check if segment is already processed or in-flight
        // Skip if: status is "transcribing" or "done", OR if it already has a transcript
        // This prevents re-enqueueing segments that were already transcribed but have stale "queued" status
        if let session = SessionStore.shared.loadSession(id: sessionId),
           let segment = session.segments.first(where: { $0.id == segmentId }) {
            // Check status
            if segment.status == "transcribing" || segment.status == "done" {
                print("[TranscriptionQueue] Segment \(segmentId) already in-flight (status=\(segment.status))")
                return
            }
            // Check if transcript already exists (segment was already processed)
            if let transcript = segment.transcriptText, !transcript.isEmpty {
                print("[TranscriptionQueue] Segment \(segmentId) already has transcript, skipping enqueue")
                return
            }
        }
        
        queue.append(workItem)
        pendingCount = queue.count
        
        // Log enqueue operation
        AppLogger.log(AppLogger.QUE, "Enqueued segment session=\(AppLogger.shortId(sessionId)) seg=\(segmentId.prefix(6)) pending=\(queue.count)")
        
        print("[TranscriptionQueue] Enqueued segment \(segmentId). Queue size: \(queue.count)")
        
        // Start processing if not already running
        startProcessingIfNeeded()
    }
    
    /// Enqueues all segments with "queued" status for a given session.
    /// Useful for resuming transcription after app restart.
    /// - Parameter sessionId: The ID of the session to scan for queued segments
    func enqueueAllQueuedSegments(for sessionId: String) {
        guard let session = SessionStore.shared.loadSession(id: sessionId) else {
            print("[TranscriptionQueue] Session \(sessionId) not found")
            return
        }
        
        // Find all segments with "queued" status
        let queuedSegments = session.segments.filter { $0.status == "queued" }
        
        print("[TranscriptionQueue] Found \(queuedSegments.count) queued segments in session \(sessionId)")
        
        // Enqueue each one
        for segment in queuedSegments {
            enqueue(sessionId: sessionId, segmentId: segment.id)
        }
    }
    
    /// Enqueues all eligible segments from all sessions for recovery on app launch.
    /// Scans all sessions and enqueues segments that are:
    /// - "queued" status (pending transcription) AND no transcript exists
    /// - "failed" status with audio file still present (retry eligible) AND no transcript exists
    /// This ensures transcription work resumes after app restart or termination.
    /// 
    /// FIX 1: Made idempotent - never enqueues segments that already have transcripts (status=done)
    func enqueueAllEligibleSegmentsOnLaunch() {
        print("[TranscriptionQueue] Starting recovery: enqueuing all eligible segments")
        
        // Load all sessions from disk
        let sessions = SessionStore.shared.loadAllSessions()
        
        var totalEnqueued = 0
        var totalSkippedDone = 0 // Segments skipped because they're already done
        var totalSkippedHasTranscript = 0 // Segments skipped because they have transcripts
        var totalMarkedMissingAudio = 0 // Segments marked failed due to missing audio (so session can finalize)
        
        for var session in sessions {
            var sessionModified = false
            for (segmentIndex, segment) in session.segments.enumerated() {
                // FIX 1a: NEVER enqueue segments with status="done" (already completed)
                if segment.status == "done" {
                    totalSkippedDone += 1
                    AppLogger.log(AppLogger.QUE, "[RECOVERY] Segment \(segment.index): status=done, decision=skip")
                    continue
                }
                
                // FIX 1b: Check if transcript exists (segment was already processed)
                let hasTranscript = segment.transcriptText != nil && !segment.transcriptText!.isEmpty
                
                // FIX 1c: If transcript exists, force status to "done" and never enqueue
                if hasTranscript {
                    totalSkippedHasTranscript += 1
                    AppLogger.log(AppLogger.QUE, "[RECOVERY] Segment \(segment.index): status=\(segment.status), transcript=exists, decision=force_done_skip")
                    
                    // Force segment to done status (fixes state desync)
                    var updatedSession = session
                    if let segmentIndex = updatedSession.segments.firstIndex(where: { $0.id == segment.id }) {
                        updatedSession.segments[segmentIndex].status = "done"
                        updatedSession.segments[segmentIndex].error = nil
                        
                        // Persist the fix
                        do {
                            try SessionStore.shared.saveSession(updatedSession)
                            print("[TranscriptionQueue] Fixed segment \(segment.id): forced status=done (had transcript)")
                        } catch {
                            print("[TranscriptionQueue] Failed to fix segment status: \(error)")
                        }
                    }
                    continue
                }
                
                // Check if segment is eligible for transcription (only if no transcript exists)
                let isQueued = segment.status == "queued"
                let isFailed = segment.status == "failed"
                let isTranscribing = segment.status == "transcribing"
                
                // Build audio file path to check existence
                let audioURL = AppPaths.audioFileURL(sessionId: session.id, audioFileName: segment.audioFileName)
                let audioExists = FileManager.default.fileExists(atPath: audioURL.path)
                
                // Check if this is a "no speech detected" error (don't retry these)
                let isNoSpeechError = segment.error?.contains("No speech detected") ?? false ||
                                      segment.error?.contains("no speech") ?? false
                
                // FIX 1d: Only enqueue if:
                // - Status is queued/transcribing AND audio exists AND no transcript
                // - OR: Status is failed AND audio exists AND no transcript AND not "no speech" error
                let shouldEnqueue = ((isQueued || isTranscribing) && audioExists && !hasTranscript) ||
                                   (isFailed && audioExists && !hasTranscript && !isNoSpeechError)
                
                if shouldEnqueue {
                    enqueue(sessionId: session.id, segmentId: segment.id)
                    totalEnqueued += 1
                    AppLogger.log(AppLogger.QUE, "[RECOVERY] Segment \(segment.index): status=\(segment.status), transcript=empty, audio=exists, decision=enqueue")
                    print("[TranscriptionQueue] Enqueued segment \(segment.id) from session \(session.id) (status=\(segment.status))")
                } else {
                    AppLogger.log(AppLogger.QUE, "[RECOVERY] Segment \(segment.index): status=\(segment.status), transcript=empty, audio=\(audioExists), decision=skip")
                    
                    // FIX: Mark segments with missing audio as failed so they become terminal.
                    // Otherwise session stays "processing" forever (recovery skips them, nothing finalizes).
                    if !audioExists {
                        session.segments[segmentIndex].status = "failed"
                        session.segments[segmentIndex].error = "Audio file not found"
                        sessionModified = true
                        totalMarkedMissingAudio += 1
                        AppLogger.log(AppLogger.QUE, "[RECOVERY] Segment \(segment.index) marked failed session=\(AppLogger.shortId(session.id)) reason=missing_audio")
                    }
                }
            }
            
            if sessionModified {
                do {
                    try SessionStore.shared.saveSession(session)
                } catch {
                    print("[TranscriptionQueue] Failed to save session after marking missing-audio segments: \(error)")
                }
            }
        }
        
        // Finalization pass: fix stuck "processing" sessions where all segments are terminal
        // (e.g. worker marked segment failed but returned early without finalizing; or we just marked no-audio segments)
        let finalizedCount = finalizeStuckProcessingSessions()
        
        print("[TranscriptionQueue] Recovery complete: enqueued=\(totalEnqueued), skipped_done=\(totalSkippedDone), skipped_has_transcript=\(totalSkippedHasTranscript), marked_missing_audio=\(totalMarkedMissingAudio), finalized_stuck=\(finalizedCount)")
        AppLogger.log(AppLogger.QUE, "[RECOVERY] complete enqueued=\(totalEnqueued) skipped_done=\(totalSkippedDone) skipped_has_transcript=\(totalSkippedHasTranscript) marked_missing_audio=\(totalMarkedMissingAudio) finalized_stuck=\(finalizedCount)")
        
        // Start processing if there's work
        if totalEnqueued > 0 {
            startProcessingIfNeeded()
        }
    }
    
    /// Waits for all segments in a specific session to finish transcription.
    /// Completes when no pending or transcribing segments remain for that session.
    /// - Parameter sessionId: The ID of the session to wait for
    func awaitDrain(sessionId: String) async {
        print("[TranscriptionQueue] Starting drain for session \(sessionId)")
        
        // Poll until no segments for this session are pending or transcribing
        while true {
            // Check queue for pending items
            let hasPendingItems = queue.contains { $0.sessionId == sessionId }
            
            // Check session store for transcribing segments
            guard let session = SessionStore.shared.loadSession(id: sessionId) else {
                print("[TranscriptionQueue] Session \(sessionId) not found during drain")
                break
            }
            
            let hasTranscribingSegments = session.segments.contains { 
                $0.status == "queued" || $0.status == "transcribing"
            }
            
            // If no pending or transcribing segments, drain is complete
            if !hasPendingItems && !hasTranscribingSegments {
                print("[TranscriptionQueue] Drain complete for session \(sessionId)")
                AppLogger.log(AppLogger.QUE, "Drain complete session=\(AppLogger.shortId(sessionId))")
                break
            }
            
            // Wait a bit before checking again
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
    }
    
    // MARK: - Processing
    
    /// Starts processing the queue if not already running
    private func startProcessingIfNeeded() {
        guard processingTask == nil else {
            // Already processing
            return
        }
        
        processingTask = Task {
            await processQueue()
            processingTask = nil
        }
    }
    
    /// Processes the queue serially until empty
    private func processQueue() async {
        isRunning = true
        
        while !queue.isEmpty {
            let workItem = queue.removeFirst()
            pendingCount = queue.count
            
            // Log dequeue operation
            AppLogger.log(AppLogger.QUE, "Dequeued segment session=\(AppLogger.shortId(workItem.sessionId)) seg=\(String(workItem.segmentId.prefix(6))) pending=\(queue.count)")
            
            print("[TranscriptionQueue] Processing segment \(workItem.segmentId)")
            
            await processWorkItem(workItem)
        }
        
        isRunning = false
        print("[TranscriptionQueue] Queue empty, processing complete")
    }
    
    /// Processes a single work item: transcribe, persist, cleanup.
    /// Uses defer to ensure finalizeSessionIfComplete is ALWAYS called on exit (including early returns
    /// for missing audio), preventing sessions from staying stuck in "processing" forever.
    private func processWorkItem(_ workItem: TranscriptionWorkItem) async {
        // Ensure we always attempt finalization on any exit path - prevents stuck "processing" sessions
        defer {
            finalizeSessionIfComplete(sessionId: workItem.sessionId)
        }
        
        // Load the session
        guard var session = SessionStore.shared.loadSession(id: workItem.sessionId) else {
            print("[TranscriptionQueue] Session \(workItem.sessionId) not found")
            return
        }
        
        // Find the segment
        guard let segmentIndex = session.segments.firstIndex(where: { $0.id == workItem.segmentId }) else {
            print("[TranscriptionQueue] Segment \(workItem.segmentId) not found in session")
            return
        }
        
        var segment = session.segments[segmentIndex]
        
        // Update status to "transcribing"
        segment.status = "transcribing"
        session.segments[segmentIndex] = segment
        
        do {
            try SessionStore.shared.saveSession(session)
        } catch {
            print("[TranscriptionQueue] Failed to save status=transcribing: \(error)")
            return
        }
        
        // Get audio file URL and verify it exists before attempting transcription
        let audioURL = AppPaths.audioFileURL(sessionId: workItem.sessionId, audioFileName: segment.audioFileName)
        let audioFileExists = FileManager.default.fileExists(atPath: audioURL.path)
        
        AppLogger.log(AppLogger.QUE, "Audio resolve session=\(AppLogger.shortId(workItem.sessionId)) seg=\(segment.index) path=\(audioURL.lastPathComponent) exists=\(audioFileExists)")
        
        guard audioFileExists else {
            print("[TranscriptionQueue] Audio file not found: \(audioURL.path)")
            AppLogger.log(AppLogger.QUE, "Segment skip session=\(AppLogger.shortId(workItem.sessionId)) seg=\(segment.index) reason=missing_audio_file")
            
            // Mark as failed so segment is terminal and session can be finalized (defer handles finalization)
            segment.status = "failed"
            segment.error = "Audio file not found"
            session.segments[segmentIndex] = segment
            
            do {
                try SessionStore.shared.saveSession(session)
            } catch {
                print("[TranscriptionQueue] Failed to save failed status: \(error)")
            }
            return
        }
        
        // Perform transcription
        do {
            let transcript = try await worker.transcribeFile(url: audioURL, sessionId: workItem.sessionId, segmentIndex: segment.index)
            
            print("[TranscriptionQueue] Transcription successful: \(transcript.prefix(50))...")
            
            // Update segment with transcript and mark as done
            segment.transcriptText = transcript
            segment.status = "done"
            segment.error = nil
            session.segments[segmentIndex] = segment
            
            // Save session before deleting audio
            try SessionStore.shared.saveSession(session)
            
            // Log successful save with status confirmation (helps debug status persistence issues)
            print("[TranscriptionQueue] ✅ Saved segment \(segment.id) with status=done and transcript length=\(transcript.count)")
            AppLogger.log(AppLogger.STORE, "Segment saved session=\(AppLogger.shortId(workItem.sessionId)) seg=\(segment.index) status=done transcriptChars=\(transcript.count)")
            
            // Delete audio file on success
            try FileManager.default.removeItem(at: audioURL)
            
            // Mark audio as deleted
            segment.audioDeletedAt = Date()
            session.segments[segmentIndex] = segment
            
            // Save final state with deletion timestamp
            try SessionStore.shared.saveSession(session)
            
            print("[TranscriptionQueue] Audio file deleted: \(audioURL.lastPathComponent)")
            
            // Enqueue extraction for this segment (async, non-blocking)
            enqueueExtractionForSegment(
                sessionId: workItem.sessionId,
                segmentId: workItem.segmentId,
                segmentIndex: segment.index,
                transcriptText: transcript,
                session: session
            )
            
        } catch {
            // Check if this is a "no speech detected" error (expected for silence)
            let errorMessage = error.localizedDescription
            let isNoSpeechError = errorMessage.contains("No speech detected") || 
                                  errorMessage.contains("no speech") ||
                                  errorMessage.contains("No speech")
            
            if isNoSpeechError {
                // FIX 2: No speech detected is NOT an error - it's expected silence
                // Log as INFO, not ERROR
                print("[TranscriptionQueue] No speech detected (silence) - marking as done")
                AppLogger.log(AppLogger.TSCR, "Transcription done (no speech) session=\(AppLogger.shortId(workItem.sessionId)) seg=\(segment.index)")
                
                // Silence is expected - mark as done with empty transcript
                segment.transcriptText = "" // Empty transcript for silent segment
                segment.status = "done"
                segment.error = nil
                session.segments[segmentIndex] = segment
                
                // Save session
                do {
                    try SessionStore.shared.saveSession(session)
                    // Log successful save with status confirmation
                    print("[TranscriptionQueue] ✅ Saved segment \(segment.id) with status=done (no speech)")
                    AppLogger.log(AppLogger.STORE, "Segment saved session=\(AppLogger.shortId(workItem.sessionId)) seg=\(segment.index) status=done transcriptChars=0 reason=no_speech")
                } catch {
                    print("[TranscriptionQueue] Failed to save done status: \(error)")
                }
                
                // Delete audio file since we're done with it
                do {
                    try FileManager.default.removeItem(at: audioURL)
                    segment.audioDeletedAt = Date()
                    session.segments[segmentIndex] = segment
                    try SessionStore.shared.saveSession(session)
                    print("[TranscriptionQueue] Audio file deleted: \(audioURL.lastPathComponent)")
                } catch {
                    print("[TranscriptionQueue] Failed to delete audio file: \(error)")
                }
            } else {
                // Real error - mark as failed (keep audio file for retry)
                segment.status = "failed"
                segment.error = errorMessage
                session.segments[segmentIndex] = segment
                
                do {
                    try SessionStore.shared.saveSession(session)
                } catch {
                    print("[TranscriptionQueue] Failed to save failed status: \(error)")
                }
            }
        }
        
        // Finalization runs via defer at top of method - ensures we never miss it on any exit path
    }
    
    /// Scans all sessions with status=processing and finalizes those where all segments are terminal.
    /// Called at end of recovery to fix sessions stuck due to missing-audio early returns or other edge cases.
    /// - Returns: Number of sessions finalized
    private func finalizeStuckProcessingSessions() -> Int {
        let sessions = SessionStore.shared.loadAllSessions()
        var count = 0
        for session in sessions where session.status == "processing" {
            let doneCount = session.segments.filter { $0.status == "done" }.count
            let failedCount = session.segments.filter { $0.status == "failed" }.count
            let queuedCount = session.segments.filter { $0.status == "queued" }.count
            let transcribingCount = session.segments.filter { $0.status == "transcribing" }.count
            
            // Only finalize if no segments are awaiting work (all are done or failed)
            if queuedCount == 0 && transcribingCount == 0 {
                finalizeSessionIfComplete(sessionId: session.id)
                count += 1
                AppLogger.log(AppLogger.QUE, "[RECOVERY] finalized session=\(AppLogger.shortId(session.id)) reason=stuck_processing done=\(doneCount) failed=\(failedCount)")
            }
        }
        return count
    }
    
    /// Checks if a session has no pending/transcribing segments and finalizes it to "complete" status.
    /// Called after each segment completes (success or failure) to ensure session transitions correctly.
    /// - Parameter sessionId: The ID of the session to check
    private func finalizeSessionIfComplete(sessionId: String) {
        // Reload session to get latest state
        guard var session = SessionStore.shared.loadSession(id: sessionId) else {
            print("[TranscriptionQueue] Session \(sessionId) not found for finalization")
            return
        }
        
        // Only finalize if session is currently in "processing" status
        guard session.status == "processing" else {
            return
        }
        
        // Check if any segments remain queued or transcribing
        let hasIncompleteSegments = session.segments.contains {
            $0.status == "queued" || $0.status == "transcribing"
        }
        
        // If no incomplete segments, mark session as complete
        if !hasIncompleteSegments {
            session.status = "complete"
            
            // Set endedAt if not already set
            if session.endedAt == nil {
                session.endedAt = Date()
            }
            
            // Compute final transcript if not already set
            if session.finalTranscriptText == nil {
                let finalTranscript = session.segments
                    .sorted { $0.index < $1.index }
                    .compactMap { $0.transcriptText }
                    .joined(separator: " ")
                session.finalTranscriptText = finalTranscript
            }
            
            // Persist completed session
            do {
                try SessionStore.shared.saveSession(session)
                let doneCount = session.segments.filter { $0.status == "done" }.count
                let failedCount = session.segments.filter { $0.status == "failed" }.count
                print("[TranscriptionQueue] Session \(sessionId) finalized to complete")
                AppLogger.log(AppLogger.STORE, "Session saved session=\(AppLogger.shortId(sessionId)) status=complete")
                AppLogger.log(AppLogger.QUE, "Drain complete session=\(AppLogger.shortId(sessionId)) done=\(doneCount) failed=\(failedCount)")
            } catch {
                print("[TranscriptionQueue] Failed to save completed session: \(error)")
            }
        }
    }
    
    // MARK: - Extraction Integration
    
    /// Enqueues extraction work for a segment after successful transcription.
    /// Runs asynchronously and does not block transcription completion.
    /// - Parameters:
    ///   - sessionId: Session identifier
    ///   - segmentId: Segment identifier
    ///   - segmentIndex: Segment index within session
    ///   - transcriptText: The completed transcript text
    ///   - session: Current session (to derive prior context)
    private func enqueueExtractionForSegment(
        sessionId: String,
        segmentId: String,
        segmentIndex: Int,
        transcriptText: String,
        session: Session
    ) {
        // Derive prior context from immediately previous segment (segmentIndex - 1)
        let priorContextText: String? = {
            guard segmentIndex > 0 else { return nil }
            
            // Find previous segment by index
            guard let prevSegment = session.segments.first(where: { $0.index == segmentIndex - 1 }) else {
                return nil
            }
            
            // Check if previous segment has transcript
            guard let prevTranscript = prevSegment.transcriptText, !prevTranscript.isEmpty else {
                return nil
            }
            
            // Take last 150 characters as context
            let maxChars = 150
            if prevTranscript.count <= maxChars {
                return prevTranscript.trimmingCharacters(in: .whitespaces)
            }
            
            return String(prevTranscript.suffix(maxChars)).trimmingCharacters(in: .whitespaces)
        }()
        
        // Build extraction work item
        let workItem = ExtractionWorkItem(
            sessionId: sessionId,
            segmentId: segmentId,
            segmentIndex: segmentIndex,
            transcriptText: transcriptText,
            priorContextText: priorContextText
        )
        
        let sessionShort = AppLogger.shortId(sessionId)
        
        // Enqueue extraction with completion handler for filtering + persistence
        ExtractionQueue.shared.enqueue(workItem: workItem) { items in
            // Handle extraction results with trust filtering
            
            // Case 1: Service returned nothing (sparse by design)
            if items.isEmpty {
                AppLogger.log(
                    AppLogger.AI,
                    "extraction_sparse session=\(sessionShort) seg=\(segmentIndex)"
                )
                return
            }
            
            // Case 2: Compute trust metrics (but don't filter)
            let confidenceThreshold = 0.65
            let strengthThreshold = 0.50
            
            // Identify low-trust items and reasons
            var lowTrustCount = 0
            var lowTrustReasons: [String] = []
            
            for item in items {
                let isLowConfidence = item.confidence < confidenceThreshold
                let isLowStrength = item.strength < strengthThreshold
                
                if isLowConfidence || isLowStrength {
                    lowTrustCount += 1
                    if isLowConfidence {
                        lowTrustReasons.append("confidence_below_\(confidenceThreshold)")
                    }
                    if isLowStrength {
                        lowTrustReasons.append("strength_below_\(strengthThreshold)")
                    }
                }
            }
            
            // Log detailed trust diagnostics if any items are low-trust
            if lowTrustCount > 0 {
                let transcriptChars = transcriptText.count
                let transcriptPreview = transcriptText
                    .replacingOccurrences(of: "\n", with: " ")
                    .prefix(140)
                let uniqueReasons = Array(Set(lowTrustReasons)).sorted()
                
                AppLogger.log(
                    AppLogger.AI,
                    "extraction_low_trust_debug session=\(sessionShort) seg=\(segmentIndex) lowTrustCount=\(lowTrustCount) reasons=[\(uniqueReasons.joined(separator: ","))] confidenceThreshold=\(confidenceThreshold) strengthThreshold=\(strengthThreshold) transcriptChars=\(transcriptChars) preview=\"\(transcriptPreview)\""
                )
                
                // Log that we're bypassing the filter (not dropping items)
                AppLogger.log(
                    AppLogger.AI,
                    "extraction_low_trust_bypassed session=\(sessionShort) seg=\(segmentIndex) wouldHaveDropped=\(lowTrustCount) actuallyDropped=0"
                )
            }
            
            // Case 3: Persist all items (trust filtering disabled)
            // Note: ExtractionStore.appendItems already logs "<STORE> Extractions saved..."
            let appendResult = ExtractionStore.shared.appendItems(sessionId: sessionId, items: items)
            
            // Case 4: Update topic aggregates with newly added items only
            // Only process items that were actually added (not skipped duplicates)
            if appendResult.added > 0 {
                // Filter to only newly added items (those not skipped by deduplication)
                // Since appendResult tells us how many were added, we take the items that were processed
                // Note: The items array has already been canonicalized, so fingerprints are stable
                
                // P1.3: Ensure MainActor isolation for TopicAggregateStore.update
                // This completion handler may run on a background thread, so we dispatch to MainActor
                Task { @MainActor in
                    TopicAggregateStore.shared.update(with: items)
                }
            }
        }
    }
}
