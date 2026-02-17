//
//  RecorderService.swift
//  Attune
//
//  Manages audio recording with automatic segment rotation.
//  Independent of view lifecycle; supports background recording.
//

import AVFoundation
import Combine

/// Singleton service that manages audio recording with automatic segment rotation.
/// Persists session and segment metadata to disk as recording progresses.
@MainActor
class RecorderService: NSObject, ObservableObject {
    
    // MARK: - Configuration
    
    /// Duration of each audio segment in seconds (3 minutes)
    /// This value is used for:
    /// - Session metadata (segmentDurationSec)
    /// - Rotation timer interval
    /// - Segment rotation logic
    private static let segmentDurationSeconds: TimeInterval = 180 // 3 minutes
    
    // MARK: - Published State
    
    /// Whether recording is currently active
    @Published var isRecording = false
    
    /// Total elapsed seconds since recording started
    @Published var elapsedSec = 0
    
    /// Current segment index (1-based for display)
    @Published var currentSegmentIndex = 0
    
    /// Current session ID (nil when not recording)
    @Published var currentSessionId: String?
    
    // MARK: - Singleton
    
    static let shared = RecorderService()
    
    // MARK: - Dependencies
    
    /// Reference to transcription queue for enqueuing closed segments
    var transcriptionQueue: TranscriptionQueue?
    
    // MARK: - Private State
    
    /// Current audio recorder instance
    private var recorder: AVAudioRecorder?
    
    /// Current session being recorded
    private var currentSession: Session?
    
    /// Timer that fires every 1 second to update elapsed time
    private var elapsedTimer: Timer?
    
    /// Timer that fires at segment rotation interval to rotate segments
    private var rotationTimer: Timer?
    
    /// Time when current segment started recording
    private var currentSegmentStartTime: Date?
    
    private override init() {
        super.init()
        setupInterruptionHandling()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public API
    
    /// Starts a new recording session with automatic segment rotation
    func startRecording() {
        guard !isRecording else { return }
        
        // Configure audio session for recording
        do {
            try configureAudioSession()
        } catch {
            print("Failed to configure audio session: \(error)")
            return
        }
        
        // Create new session
        let sessionId = UUID().uuidString
        let session = Session(
            id: sessionId,
            startedAt: Date(),
            status: "recording",
            segmentDurationSec: Int(RecorderService.segmentDurationSeconds), // Use constant: 180 seconds (3 minutes)
            segments: []
        )
        
        currentSession = session
        currentSessionId = sessionId
        
        // Log recording start
        AppLogger.log(AppLogger.REC, "Recording started session=\(AppLogger.shortId(sessionId))")
        
        // Persist initial session
        do {
            try SessionStore.shared.saveSession(session)
        } catch {
            print("Failed to save initial session: \(error)")
            return
        }
        
        // Create audio directory for this session
        do {
            try AppPaths.ensureAudioDirectory(sessionId: sessionId)
        } catch {
            print("Failed to create audio directory: \(error)")
            return
        }
        
        // Start recording first segment
        currentSegmentIndex = 1
        elapsedSec = 0
        isRecording = true
        
        startSegment(index: 1)
        startTimers()
    }
    
    /// Stops the current recording session
    /// FIX 3: Ensures session.status is set to "processing" ONCE and never reverts to "recording"
    func stopRecording() {
        guard isRecording else { return }
        
        // Log recording stop
        if let sessionId = currentSessionId {
            AppLogger.log(AppLogger.REC, "Recording stop requested session=\(AppLogger.shortId(sessionId))")
        }
        
        // Stop timers
        stopTimers()
        
        // Stop current recorder and finalize segment
        stopCurrentRecorder()
        
        // Update session status and finalize last segment
        guard let session = currentSession else { return } // Require an in-memory session anchor
        let sessionId = session.id // Capture for reuse
        let latest = SessionStore.shared.loadSession(id: sessionId) ?? session // Reload latest disk state to avoid overwriting newer worker writes
        var mergedSession = latest // Start from disk state
        mergedSession.endedAt = Date() // Ensure endedAt is set on the merged copy
        
        // FIX 3: Set status to "processing" ONCE - this is a hard transition
        // After this point, the session should NEVER be saved with status="recording" again
        mergedSession.status = "processing" // Preserve hard transition on the merged copy
        
        // Mark last segment as queued if it exists
        if let lastInMemory = session.segments.last, // Identify the segment RecorderService is finalizing
           let mergedIndex = mergedSession.segments.firstIndex(where: { $0.id == lastInMemory.id }) { // Match by ID to avoid index drift
            var mergedSegment = mergedSession.segments[mergedIndex] // Work on the matched segment
            let hasTranscript = mergedSegment.transcriptText?.isEmpty == false // Check if transcript exists
            let isDone = mergedSegment.status == "done" // Check if already done
            
            if !isDone && !hasTranscript { // Only modify if not already completed
                mergedSegment.endedAt = Date() // Finalize end time
                mergedSegment.status = "queued" // Move to queued for transcription
                mergedSession.segments[mergedIndex] = mergedSegment // Persist into merged session
                
                let segmentId = mergedSegment.id // Capture for enqueue
                
                print("[RecorderService] save:stopRecording session=\(sessionId) summary=\(cappedSegmentSummary(mergedSession.segments))") // Debug summary before save
                
                // Persist session state with processing status (ONCE)
                do {
                    try SessionStore.shared.saveSession(mergedSession) // Save merged session preserving completed segments
                    print("[RecorderService] ✅ Session \(AppLogger.shortId(sessionId)) transitioned to status=processing (final)") // Confirmation log
                    currentSession = mergedSession // Keep in-memory session aligned with disk state
                    
                    // Enqueue the last segment for transcription
                    transcriptionQueue?.enqueue(sessionId: mergedSession.id, segmentId: segmentId) // Queue the finalized segment
                    print("[RecorderService] Enqueued final segment \(segmentId) for transcription") // Trace enqueue
                    
                    // Start async drain process (does not block UI)
                    Task {
                        await drainAndFinalize(sessionId: sessionId) // Drain after enqueue
                    }
                } catch {
                    print("Failed to save final session: \(error)") // Error logging
                }
            } else {
                print("[RecorderService] stopRecording skipped modifying segment \(mergedSegment.index) (done or has transcript)") // Log skip when already done
            }
        }
        
        // Reset UI state immediately (session continues processing in background)
        // IMPORTANT: Clear currentSession to prevent any further saves with stale status
        isRecording = false
        currentSession = nil
        currentSessionId = nil
        currentSegmentIndex = 0
        elapsedSec = 0
    }
    
    /// Drains the transcription queue for a session and finalizes it.
    /// This runs asynchronously after stopRecording() to avoid blocking the main thread.
    /// - Parameter sessionId: The ID of the session to drain and finalize
    private func drainAndFinalize(sessionId: String) async {
        print("[RecorderService] Starting drain and finalize for session \(sessionId)")
        
        // Wait for all segments in this session to finish transcribing
        await transcriptionQueue?.awaitDrain(sessionId: sessionId)
        
        // Reload session to get updated segment transcripts
        guard var session = SessionStore.shared.loadSession(id: sessionId) else {
            print("[RecorderService] Session \(sessionId) not found after drain")
            return
        }
        
        // Compute final transcript by concatenating segment transcripts in order
        let finalTranscript = session.segments
            .sorted { $0.index < $1.index }
            .compactMap { $0.transcriptText }
            .joined(separator: " ")
        
        // Update session to complete status
        session.status = "complete"
        session.finalTranscriptText = finalTranscript
        
        // Persist final session state
        do {
            try SessionStore.shared.saveSession(session)
            print("[RecorderService] Session \(sessionId) marked complete with transcript (\(finalTranscript.count) chars)")
        } catch {
            print("[RecorderService] Failed to save completed session: \(error)")
        }
    }
    
    // MARK: - Audio Session Configuration
    
    /// Configures AVAudioSession for recording with background support
    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        
        // Set category to record, with Bluetooth microphone support
        try audioSession.setCategory(.record, mode: .default, options: [.allowBluetooth])
        
        // Activate the audio session
        try audioSession.setActive(true)
    }
    
    // MARK: - Segment Management
    
    /// Starts recording a new segment
    private func startSegment(index: Int) {
        guard let session = currentSession else { return } // Ensure we have an in-memory session to anchor the append
        
        let sessionId = session.id // Capture the session ID for disk lookups and logs
        let latest = SessionStore.shared.loadSession(id: sessionId) ?? session // Reload latest session from disk to avoid overwriting newer worker writes
        var mergedSession = latest // Work on a mutable copy that includes any worker updates
        
        // Create segment metadata
        let segmentId = UUID().uuidString // Unique segment identifier
        let audioFileName = String(format: "segment_%03d.m4a", index) // 1-based filename to match live queue pattern
        
        let segment = Segment(
            id: segmentId,
            sessionId: session.id,
            index: index - 1,  // Zero-based for storage
            startedAt: Date(),
            audioFileName: audioFileName,
            status: "writing"
        ) // Build new segment ready to be appended
        
        // Add segment to session
        mergedSession.segments.append(segment) // Append without touching existing segments
        currentSession = mergedSession // Keep in-memory reference aligned with disk-bound data
        
        // Log segment opened
        AppLogger.log(AppLogger.SEG, "Segment opened session=\(AppLogger.shortId(session.id)) seg=\(index - 1)") // Trace segment creation
        print("[RecorderService] save:startSegment session=\(sessionId) summary=\(cappedSegmentSummary(mergedSession.segments))") // Debug summary before save
        
        // Persist session with new segment
        do {
            try SessionStore.shared.saveSession(mergedSession) // Save merged session that includes latest-from-disk state plus new segment
        } catch {
            print("Failed to save session with new segment: \(error)")
        }
        
        // Start audio recorder for this segment
        let audioURL = AppPaths.audioFileURL(sessionId: session.id, audioFileName: audioFileName)
        
        // Log audio file creation
        AppLogger.log(AppLogger.FILE, "Audio file created session=\(AppLogger.shortId(session.id)) seg=\(index - 1) file=\(audioFileName)")
        
        startRecorder(url: audioURL)
        currentSegmentStartTime = Date()
    }
    
    /// Rotates to the next segment (called by rotation timer)
    @objc private func rotateSegment() {
        guard isRecording, let session = currentSession else { return } // Require active recording and an in-memory anchor
        
        // Stop current recorder and finalize segment
        stopCurrentRecorder()
        
        // Update last segment to "queued" status
        if let lastInMemory = session.segments.last { // Only proceed if we have a segment to close
            let sessionId = session.id // Capture ID for disk lookups
            let latest = SessionStore.shared.loadSession(id: sessionId) ?? session // Reload latest session from disk
            var mergedSession = latest // Start from disk state to avoid overwriting
            
            if let mergedIndex = mergedSession.segments.firstIndex(where: { $0.id == lastInMemory.id }) { // Match segment by ID
                var mergedSegment = mergedSession.segments[mergedIndex] // Work on matched segment
                let hasTranscript = mergedSegment.transcriptText?.isEmpty == false // Check transcript presence
                let isDone = mergedSegment.status == "done" // Check completion
                
                if !isDone && !hasTranscript { // Only modify if not already completed
                    mergedSegment.endedAt = Date() // Finalize end time
                    mergedSegment.status = "queued" // Move to queued for transcription
                    mergedSession.segments[mergedIndex] = mergedSegment // Persist into merged session
                    
                    AppLogger.log(AppLogger.SEG, "Segment closed session=\(AppLogger.shortId(session.id)) seg=\(mergedSegment.index)") // Trace closure
                    print("[RecorderService] save:rotateSegment session=\(sessionId) summary=\(cappedSegmentSummary(mergedSession.segments))") // Debug summary before save
                    
                    do {
                        try SessionStore.shared.saveSession(mergedSession) // Save merged state
                        currentSession = mergedSession // Keep in-memory aligned
                        
                        // Enqueue segment for transcription after successful persistence
                        transcriptionQueue?.enqueue(sessionId: mergedSession.id, segmentId: mergedSegment.id) // Queue this segment
                        print("[RecorderService] Enqueued segment \(mergedSegment.id) for transcription") // Trace enqueue
                    } catch {
                        print("Failed to save session after rotation: \(error)") // Error logging
                    }
                } else {
                    print("[RecorderService] rotateSegment skipped modifying segment \(mergedSegment.index) (done or has transcript)") // Log skip if already completed
                }
            }
        }
        
        // Start next segment
        currentSegmentIndex += 1
        startSegment(index: currentSegmentIndex)
    }
    
    // MARK: - AVAudioRecorder Management
    
    /// Starts a new AVAudioRecorder instance writing to the specified URL
    private func startRecorder(url: URL) {
        // Audio settings: AAC format, 44.1kHz, mono
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.delegate = self
            newRecorder.record()
            recorder = newRecorder
        } catch {
            print("Failed to start recorder: \(error)")
        }
    }
    
    /// Stops the current recorder and finalizes the audio file
    private func stopCurrentRecorder() {
        recorder?.stop()
        recorder = nil
    }
    
    // MARK: - Timer Management
    
    /// Starts the elapsed timer (1 second) and rotation timer (300 seconds)
    private func startTimers() {
        // Elapsed timer: fires every 1 second
        // Use .common run loop mode to continue firing when app is backgrounded
        let elapsed = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedSec += 1
            }
        }
        RunLoop.current.add(elapsed, forMode: .common)
        elapsedTimer = elapsed
        
        // Rotation timer: fires at segment duration interval (180 seconds = 3 minutes)
        // Use .common run loop mode to continue firing when app is backgrounded
        let rotation = Timer(timeInterval: RecorderService.segmentDurationSeconds, target: self, selector: #selector(rotateSegment), userInfo: nil, repeats: true)
        RunLoop.current.add(rotation, forMode: .common)
        rotationTimer = rotation
    }
    
    /// Stops and invalidates all timers
    private func stopTimers() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        
        rotationTimer?.invalidate()
        rotationTimer = nil
    }
    
    // MARK: - Interruption Handling
    
    /// Sets up AVAudioSession interruption notification observer
    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }
    
    /// Handles AVAudioSession interruption notifications (phone calls, Siri, route changes)
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        Task { @MainActor in
            switch type {
            case .began:
                handleInterruptionBegan(userInfo: userInfo)
            case .ended:
                handleInterruptionEnded(userInfo: userInfo)
            @unknown default:
                break
            }
        }
    }
    
    /// Handles the beginning of an audio interruption
    private func handleInterruptionBegan(userInfo: [AnyHashable: Any]) {
        guard isRecording, let session = currentSession else { return } // Require active recording and session anchor
        let sessionId = session.id // Capture session ID for disk lookups
        let latest = SessionStore.shared.loadSession(id: sessionId) ?? session // Reload latest session to avoid overwriting worker changes
        var mergedSession = latest // Work on merged copy
        
        // Extract interruption reason if available (for logging purposes)
        let reason: String
        if let reasonValue = userInfo[AVAudioSessionInterruptionReasonKey] as? UInt,
           let interruptionReason = AVAudioSession.InterruptionReason(rawValue: reasonValue) {
            switch interruptionReason {
            case .default:
                reason = "default"
            case .appWasSuspended:
                reason = "app suspended"
            case .builtInMicMuted:
                reason = "mic muted"
            @unknown default:
                reason = "unknown"
            }
        } else {
            reason = "unspecified"
        }
        
        // Log interruption (as warning, not error, since we'll handle it gracefully)
        AppLogger.log(AppLogger.REC, "Interruption detected session=\(AppLogger.shortId(session.id)) reason=\(reason)")
        
        // Stop recorder cleanly to finalize the audio file
        stopCurrentRecorder()
        
        // Invalidate timers since recording is ending
        stopTimers()
        
        // Track if we have any valid segments to process
        var hasValidSegments = false // Initialize validity tracker
        
        // Finalize current segment if it exists
        if let lastInMemory = session.segments.last, // Only finalize if a segment exists
           let mergedIndex = mergedSession.segments.firstIndex(where: { $0.id == lastInMemory.id }) { // Match by ID to avoid index drift
            var mergedSegment = mergedSession.segments[mergedIndex] // Work on matched segment
            let hasTranscript = mergedSegment.transcriptText?.isEmpty == false // Check transcript presence
            let isDone = mergedSegment.status == "done" // Check completion
            
            if !isDone && !hasTranscript { // Only modify if not already completed
                mergedSegment.endedAt = Date() // Finalize end time
                
                // Check if audio file exists and has content before enqueueing
                let audioFileName = mergedSegment.audioFileName // Use stored filename
                let audioURL = AppPaths.audioFileURL(sessionId: session.id, audioFileName: audioFileName) // Resolve path
                
                if FileManager.default.fileExists(atPath: audioURL.path),
                   let attrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
                   let fileSize = attrs[.size] as? Int64, fileSize > 0 { // Validate audio presence
                    // File exists and has content → enqueue for transcription
                    mergedSegment.status = "queued" // Move to queued for later processing
                    let segmentId = mergedSegment.id // Capture ID for enqueue
                    mergedSession.segments[mergedIndex] = mergedSegment // Persist changes locally
                    hasValidSegments = true // Note presence of valid work
                    
                    AppLogger.log(AppLogger.SEG, "Segment finalized after interruption session=\(AppLogger.shortId(session.id)) seg=\(mergedSegment.index) status=queued") // Trace finalization
                    
                    // Enqueue for transcription after persisting
                    transcriptionQueue?.enqueue(sessionId: mergedSession.id, segmentId: segmentId) // Queue the segment
                } else {
                    // No file or empty → mark failed (but don't fail the entire session)
                    mergedSegment.status = "failed" // Mark as failed due to missing/empty audio
                    mergedSegment.error = "Audio file missing or empty after interruption" // Capture error
                    mergedSession.segments[mergedIndex] = mergedSegment // Persist locally
                    
                    AppLogger.log(AppLogger.ERR, "Segment failed after interruption session=\(AppLogger.shortId(session.id)) seg=\(mergedSegment.index) reason=no audio") // Log failure
                }
            } else {
                print("[RecorderService] interruption skip segment \(mergedSegment.index) (done or has transcript)") // Log skip when completed
            }
        }
        
        // FIX 3: Update session status with hard transition (never revert to "recording")
        mergedSession.endedAt = Date() // Finalize session end time on merged copy
        
        // If we have valid segments, treat this as a successful recording that was interrupted
        // Set status to "processing" so it will be transcribed and finalized normally
        if hasValidSegments { // If we captured any valid work
            // FIX 3: Hard transition to "processing" - never save as "recording" again
            mergedSession.status = "processing" // Move session to processing on merged copy
            // Store interruption info in lastError for reference, but don't treat as failure
            mergedSession.lastError = "Recording interrupted by \(reason) - saved successfully" // Preserve interruption note
            
            AppLogger.log(AppLogger.REC, "Session interrupted but saved session=\(AppLogger.shortId(session.id)) status=processing segments=\(mergedSession.segments.count)") // Trace session status change
            print("[RecorderService] save:interruption session=\(sessionId) summary=\(cappedSegmentSummary(mergedSession.segments))") // Debug summary before save
            
            // Persist session with processing status (ONCE)
            do {
                try SessionStore.shared.saveSession(mergedSession) // Save merged state
                currentSession = mergedSession // Keep in-memory aligned
                print("[RecorderService] ✅ Session \(AppLogger.shortId(session.id)) transitioned to status=processing after interruption (final)") // Confirmation log
                AppLogger.log(AppLogger.STORE, "Session saved after interruption session=\(AppLogger.shortId(session.id)) status=processing") // Store log
                
                // Start async drain and finalize process (same as normal stop)
                let sessionId = mergedSession.id // Capture for async
                Task {
                    await drainAndFinalize(sessionId: sessionId) // Drain after interruption
                }
            } catch {
                AppLogger.log(AppLogger.ERR, "Failed to persist session after interruption session=\(AppLogger.shortId(session.id)) error=\(error.localizedDescription)") // Error log
            }
        } else {
            // No valid segments → mark as error (nothing to save)
            mergedSession.status = "error" // Mark session as errored
            mergedSession.lastError = "Interruption: \(reason) - no valid audio captured" // Capture reason
            
            AppLogger.log(AppLogger.ERR, "Session interrupted with no valid audio session=\(AppLogger.shortId(session.id)) status=error") // Trace error path
            print("[RecorderService] save:interruption-no-valid session=\(sessionId) summary=\(cappedSegmentSummary(mergedSession.segments))") // Debug summary before save
            
            // Persist session with error status
            do {
                try SessionStore.shared.saveSession(mergedSession) // Save merged error state
                currentSession = mergedSession // Keep in-memory aligned
                AppLogger.log(AppLogger.STORE, "Session saved after interruption session=\(AppLogger.shortId(session.id)) status=error") // Store log
            } catch {
                AppLogger.log(AppLogger.ERR, "Failed to persist session after interruption session=\(AppLogger.shortId(session.id)) error=\(error.localizedDescription)") // Error log
            }
        }
        
        // Reset published state (UI returns to idle)
        isRecording = false
        currentSession = nil
        currentSessionId = nil
        currentSegmentIndex = 0
        elapsedSec = 0
    }
    
    /// Handles the end of an audio interruption
    private func handleInterruptionEnded(userInfo: [AnyHashable: Any]) {
        // Extract session ID if available (may be nil if already cleared)
        let sessionId = currentSessionId ?? "none"
        
        // Log interruption ended
        AppLogger.log(AppLogger.REC, "Interruption ended session=\(AppLogger.shortId(sessionId))")
        
        // Do not auto-resume - user must manually start new recording
    }
}

// MARK: - Debug helpers

private func describeSegments(_ segments: [Segment]) -> String { // Builds a readable description for each segment
    return segments.map { segment in // Map each segment to a short string
        let transcriptChars = segment.transcriptText?.count ?? 0 // Count transcript length safely
        return "seg \(segment.index) status=\(segment.status) transcriptChars=\(transcriptChars) audio=\(segment.audioFileName)" // Compose description for this segment
    }.joined(separator: " | ") // Join all descriptions with separators
}

private func cappedSegmentSummary(_ segments: [Segment]) -> String { // Limits summary to head/tail to keep logs short
    let total = segments.count // Total segment count
    if total <= 10 { // If small, show all
        return describeSegments(segments) // Return full description
    }
    let head = Array(segments.prefix(5)) // Take first five segments
    let tail = Array(segments.suffix(5)) // Take last five segments
    return describeSegments(head) + " ... " + describeSegments(tail) // Combine head and tail with ellipsis
}

// MARK: - AVAudioRecorderDelegate

extension RecorderService: AVAudioRecorderDelegate {
    
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // Recording finished (either by rotation or stop)
        if !flag {
            print("Recording finished unsuccessfully")
        }
    }
    
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        // Handle encoding errors
        if let error = error {
            print("Recorder encode error: \(error)")
        }
    }
}
