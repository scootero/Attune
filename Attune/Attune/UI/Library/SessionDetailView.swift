//
//  SessionDetailView.swift
//  Attune
//
//  Shows session metadata, segment list, and joined transcript.
//

import SwiftUI

struct SessionDetailView: View {
    /// Session ID to load
    let sessionId: String
    
    /// Loaded session
    @State private var session: Session?
    
    #if DEBUG
    /// Alert message to show after debug actions
    @State private var debugAlertMessage: String?
    /// Whether to show the debug alert
    @State private var showDebugAlert = false
    #endif
    
    var body: some View {
        Group {
            if let session = session {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Session metadata
                        SessionMetadataSection(session: session)
                        
                        Divider()
                        
                        // Insights summary
                        InsightsSummarySection(sessionId: session.id)
                        
                        Divider()
                        
                        // Segments list
                        SegmentsListSection(segments: session.segments)
                        
                        Divider()
                        
                        // Joined transcript
                        JoinedTranscriptSection(session: session)
                        
                        #if DEBUG
                        Divider()
                        
                        // Debug actions
                        DebugActionsSection(
                            session: session,
                            onRetryFailed: retryFailedSegments,
                            onResumeQueued: resumeQueuedSegments
                        )
                        #endif
                    }
                    .padding()
                }
                .navigationTitle("Session \(session.shortId)")
                .navigationBarTitleDisplayMode(.inline)
                #if DEBUG
                .alert("Debug Action", isPresented: $showDebugAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(debugAlertMessage ?? "")
                }
                #endif
            } else {
                // Loading or not found
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    
                    Text("Session Not Found")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            loadSession()
        }
    }
    
    /// Loads the session from disk
    private func loadSession() {
        session = SessionStore.shared.loadSession(id: sessionId)
    }
    
    #if DEBUG
    // MARK: - Debug Actions
    
    /// Retries all failed segments for this session.
    /// Transitions failed segments back to queued status and enqueues them for transcription.
    private func retryFailedSegments() {
        guard var currentSession = session else { return }
        
        var retriedCount = 0
        
        // Find segments that are eligible for retry:
        // - status is "failed"
        // - transcriptText is missing (nil or empty)
        // - audio file exists
        for i in 0..<currentSession.segments.count {
            var segment = currentSession.segments[i]
            
            // Check eligibility
            let isFailed = segment.status == "failed"
            let hasNoTranscript = segment.transcriptText == nil || segment.transcriptText!.isEmpty
            let audioExists = AppPaths.audioFileExists(sessionId: currentSession.id, audioFileName: segment.audioFileName)
            
            if isFailed && hasNoTranscript && audioExists {
                // Transition from failed to queued
                segment.status = "queued"
                segment.error = nil // Clear error message
                currentSession.segments[i] = segment
                
                // Log state transition
                AppLogger.log(AppLogger.STORE, "segment_status_change session=\(AppLogger.shortId(currentSession.id)) seg=\(segment.index) from=failed to=queued")
                
                retriedCount += 1
            }
        }
        
        // Persist the updated session
        do {
            try SessionStore.shared.saveSession(currentSession)
            
            // Enqueue the retried segments
            for segment in currentSession.segments where segment.status == "queued" {
                TranscriptionQueue.shared.enqueue(sessionId: currentSession.id, segmentId: segment.id)
            }
            
            // Log the retry action
            AppLogger.log(AppLogger.QUE, "[retry] enqueued_failed session=\(AppLogger.shortId(currentSession.id)) count=\(retriedCount)")
            
            // Update local state
            session = currentSession
            
            // Show alert
            debugAlertMessage = "Enqueued \(retriedCount) failed segment\(retriedCount == 1 ? "" : "s")"
            showDebugAlert = true
            
        } catch {
            print("[SessionDetailView] Failed to save session during retry: \(error)")
            debugAlertMessage = "Error: \(error.localizedDescription)"
            showDebugAlert = true
        }
    }
    
    /// Resumes processing for all queued segments in this session.
    /// Enqueues any segments with "queued" status without changing their state.
    /// 
    /// NOTE: With FIX 1, the enqueue() function now checks if segments have transcripts
    /// and will skip re-enqueueing segments that are already done (even if status is stale).
    /// This makes the resume operation safe and idempotent.
    private func resumeQueuedSegments() {
        guard let currentSession = session else { return }
        
        // Find segments with "queued" status
        // Ignore segments that are already processing (transcribing) or done
        let queuedSegments = currentSession.segments.filter { segment in
            segment.status == "queued"
        }
        
        let count = queuedSegments.count
        
        if count == 0 {
            // No queued segments to resume
            debugAlertMessage = "No queued segments"
            showDebugAlert = true
            return
        }
        
        // Enqueue each queued segment
        // The enqueue() function will skip segments that already have transcripts (FIX 1)
        for segment in queuedSegments {
            TranscriptionQueue.shared.enqueue(sessionId: currentSession.id, segmentId: segment.id)
        }
        
        // Log the resume action
        AppLogger.log(AppLogger.QUE, "[resume] enqueued_queued session=\(AppLogger.shortId(currentSession.id)) count=\(count)")
        
        // Show alert
        debugAlertMessage = "Enqueued \(count) queued segment\(count == 1 ? "" : "s")"
        showDebugAlert = true
    }
    #endif
}

// MARK: - Session Metadata Section

struct SessionMetadataSection: View {
    let session: Session
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session Info")
                .font(.headline)
            
            MetadataRow(label: "ID", value: session.id)
            MetadataRow(label: "Status", value: session.status)
            MetadataRow(label: "Started", value: session.startedAt.formatted(date: .abbreviated, time: .shortened))
            
            if let endedAt = session.endedAt {
                MetadataRow(label: "Ended", value: endedAt.formatted(date: .abbreviated, time: .shortened))
            }
            
            if let duration = session.durationFormatted {
                MetadataRow(label: "Duration", value: duration)
            }
            
            MetadataRow(label: "Segment Duration", value: "\(session.segmentDurationSec)s")
            MetadataRow(label: "Total Segments", value: "\(session.segments.count)")
            
            if let error = session.lastError {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Error:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
    }
}

// MARK: - Segments List Section

struct SegmentsListSection: View {
    let segments: [Segment]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Segments")
                .font(.headline)
            
            ForEach(segments.sorted { $0.index < $1.index }) { segment in
                NavigationLink(destination: SegmentDetailView(sessionId: segment.sessionId, segmentId: segment.id)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Segment \(segment.index)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text(segment.startedAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 8) {
                                StatusBadge(status: segment.status)
                                
                                if segment.transcriptText != nil && !segment.transcriptText!.isEmpty {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Joined Transcript Section

struct JoinedTranscriptSection: View {
    let session: Session
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Full Transcript")
                .font(.headline)
            
            let transcript = session.joinedTranscript()
            
            if transcript.isEmpty || transcript.contains("Missing transcript") {
                Text(transcript.isEmpty ? "No transcript available yet" : transcript)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            } else {
                Text(transcript)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
        }
    }
}

// MARK: - Insights Summary Section

/// Displays a count summary of insights extracted from this session
struct InsightsSummarySection: View {
    let sessionId: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Insights")
                .font(.headline)
            
            // Load extractions for this session
            let extractions = ExtractionStore.shared.loadExtractions(sessionId: sessionId)
            
            // Total count
            HStack {
                Text("Total:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(extractions.count)")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            // Count by type
            if !extractions.isEmpty {
                let eventCount = extractions.filter { $0.type == "event" }.count
                let intentionCount = extractions.filter { $0.type == "intention" }.count
                let commitmentCount = extractions.filter { $0.type == "commitment" }.count
                let stateCount = extractions.filter { $0.type == "state" }.count
                
                HStack(spacing: 16) {
                    if eventCount > 0 {
                        TypeCountBadge(type: "event", count: eventCount)
                    }
                    if intentionCount > 0 {
                        TypeCountBadge(type: "intention", count: intentionCount)
                    }
                    if commitmentCount > 0 {
                        TypeCountBadge(type: "commitment", count: commitmentCount)
                    }
                    if stateCount > 0 {
                        TypeCountBadge(type: "state", count: stateCount)
                    }
                }
            }
        }
    }
}

/// Displays a single type count in a badge format
struct TypeCountBadge: View {
    let type: String
    let count: Int
    
    var body: some View {
        HStack(spacing: 4) {
            Text(type)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("\(count)")
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.15))
        .cornerRadius(6)
    }
}

#if DEBUG
// MARK: - Debug Actions Section

struct DebugActionsSection: View {
    let session: Session
    let onRetryFailed: () -> Void
    let onResumeQueued: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Debug Actions")
                .font(.headline)
                .foregroundColor(.orange)
            
            Text("Development tools for testing transcription recovery")
                .font(.caption)
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                // Retry failed segments button
                Button(action: onRetryFailed) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry failed (\(failedSegmentCount))")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(failedSegmentCount > 0 ? Color.orange : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(failedSegmentCount == 0)
                
                // Resume queued segments button
                Button(action: onResumeQueued) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Resume queued (\(queuedSegmentCount))")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(queuedSegmentCount > 0 ? Color.blue : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(queuedSegmentCount == 0)
            }
        }
    }
    
    /// Count of failed segments that are eligible for retry
    /// (failed status, no transcript, audio exists)
    private var failedSegmentCount: Int {
        session.segments.filter { segment in
            let isFailed = segment.status == "failed"
            let hasNoTranscript = segment.transcriptText == nil || segment.transcriptText!.isEmpty
            let audioExists = AppPaths.audioFileExists(sessionId: session.id, audioFileName: segment.audioFileName)
            return isFailed && hasNoTranscript && audioExists
        }.count
    }
    
    /// Count of queued segments that can be resumed
    private var queuedSegmentCount: Int {
        session.segments.filter { $0.status == "queued" }.count
    }
}
#endif

#Preview {
    NavigationView {
        SessionDetailView(sessionId: "test-session-id")
    }
}
