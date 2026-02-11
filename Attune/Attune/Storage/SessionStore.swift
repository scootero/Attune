//
//  SessionStore.swift
//  Attune
//
//  Handles persistence of Session objects to/from JSON files.
//

import Foundation

/// Manages loading and saving of Session objects to disk using JSON.
/// Each session is stored as a separate JSON file in the Sessions directory.
@MainActor
class SessionStore {
    
    // MARK: - Initialization
    
    /// Shared singleton instance
    static let shared = SessionStore()
    
    private init() {
        // Ensure directories exist on initialization
        try? AppPaths.ensureDirectoriesExist()
    }
    
    // MARK: - Loading
    
    /// Loads all sessions from disk
    /// Returns an array of all persisted sessions, or empty array if none exist
    func loadAllSessions() -> [Session] {
        let fileManager = FileManager.default
        
        // Ensure sessions directory exists
        guard let files = try? fileManager.contentsOfDirectory(at: AppPaths.sessionsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        
        // Configure decoder with ISO8601 date strategy
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        // Filter for JSON files and load each one
        let sessions = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Session? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Session.self, from: data)
            }
        
        // Sort by startedAt descending (newest first)
        return sessions.sorted { $0.startedAt > $1.startedAt }
    }
    
    /// Loads a specific session by ID
    /// Returns the session if it exists, nil otherwise
    func loadSession(id: String) -> Session? {
        let fileURL = AppPaths.sessionFileURL(sessionId: id)
        
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        // Configure decoder with ISO8601 date strategy
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try? decoder.decode(Session.self, from: data)
    }
    
    /// Loads all segments across all sessions as a flat list
    /// Returns an array of tuples containing (session, segment) pairs
    func loadAllSegments() -> [(session: Session, segment: Segment)] {
        let sessions = loadAllSessions()
        
        var allSegments: [(session: Session, segment: Segment)] = []
        
        for session in sessions {
            for segment in session.segments {
                allSegments.append((session: session, segment: segment))
            }
        }
        
        return allSegments
    }
    
    // MARK: - Saving
    
    /// Saves a session to disk (atomic write)
    /// The session is encoded to JSON and written atomically to prevent corruption
    func saveSession(_ session: Session) throws {
        // Ensure directories exist
        try AppPaths.ensureDirectoriesExist()
        
        let fileURL = AppPaths.sessionFileURL(sessionId: session.id)
        
        // Encode session to JSON with pretty printing for readability
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(session)
        
        // Atomic write to prevent corruption
        try data.write(to: fileURL, options: .atomic)
        
        // Log session save
        AppLogger.log(AppLogger.STORE, "Session saved session=\(AppLogger.shortId(session.id)) status=\(session.status)")
    }
    
    /// Updates an existing session (convenience method that calls saveSession)
    func updateSession(_ session: Session) throws {
        try saveSession(session)
    }
    
    /// Updates a specific segment within a session.
    /// Convenience method that loads the session, updates the segment, and saves.
    /// - Parameters:
    ///   - sessionId: The ID of the session containing the segment
    ///   - segmentId: The ID of the segment to update
    ///   - updateBlock: A closure that modifies the segment
    func updateSegment(sessionId: String, segmentId: String, updateBlock: (inout Segment) -> Void) throws {
        guard var session = loadSession(id: sessionId) else {
            throw SessionStoreError.sessionNotFound(sessionId)
        }
        
        guard let segmentIndex = session.segments.firstIndex(where: { $0.id == segmentId }) else {
            throw SessionStoreError.segmentNotFound(segmentId)
        }
        
        updateBlock(&session.segments[segmentIndex])
        
        try saveSession(session)
    }
    
    // MARK: - Deletion (for future use)
    
    /// Deletes a session file from disk
    func deleteSession(id: String) throws {
        let fileURL = AppPaths.sessionFileURL(sessionId: id)
        try FileManager.default.removeItem(at: fileURL)
    }
    
    // MARK: - Recovery
    
    /// Performs recovery on app launch to reconcile incomplete sessions and segments.
    /// This method scans all sessions and:
    /// - Marks sessions that were "recording" as "error" (app terminated during recording)
    /// - Resets segments that were "transcribing" back to "queued" (transcription was interrupted)
    /// - Fixes "failed" segments with "No speech detected" errors (marks as done with empty transcript)
    /// - Preserves audio files (never deletes during recovery)
    /// Returns the list of all sessions after recovery (for further processing)
    func recoverIncompleteSessionsOnLaunch() -> [Session] {
        print("[SessionStore] Starting recovery on app launch")
        
        var sessions = loadAllSessions()
        var modifiedSessions: [Session] = []
        
        for var session in sessions {
            var sessionModified = false
            
            // Check if session was in an incomplete state
            if session.status == "recording" || session.status == "stopping" || session.status == "processing" {
                print("[SessionStore] Recovering session \(session.id) with status=\(session.status)")
                
                // If session was recording when app terminated, check if we have valid segments
                if session.status == "recording" {
                    // Count segments with valid audio files
                    var validSegmentCount = 0
                    for segment in session.segments {
                        let audioURL = AppPaths.audioFileURL(sessionId: session.id, audioFileName: segment.audioFileName)
                        if FileManager.default.fileExists(atPath: audioURL.path),
                           let attrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
                           let fileSize = attrs[.size] as? Int64, fileSize > 0 {
                            validSegmentCount += 1
                        }
                    }
                    
                    // If we have valid segments, treat as interrupted recording (not error)
                    if validSegmentCount > 0 {
                        session.status = "processing"
                        session.lastError = "App terminated during recording - \(validSegmentCount) segment(s) recovered"
                        print("[SessionStore] Recovered session \(session.id) with \(validSegmentCount) valid segments, marked as processing")
                    } else {
                        // No valid segments → mark as error
                        session.status = "error"
                        session.lastError = "App terminated during recording - no valid audio captured"
                        print("[SessionStore] Marked session \(session.id) as error (no valid segments)")
                    }
                    sessionModified = true
                }
                
                // For segments: reset "transcribing" back to "queued" ONLY if no transcript exists
                // FIX 1: Made idempotent - don't reset segments that already have transcripts
                for i in 0..<session.segments.count {
                    var segment = session.segments[i]
                    
                    if segment.status == "transcribing" {
                        // Check if transcript already exists (segment was actually completed)
                        let hasTranscript = segment.transcriptText != nil && !segment.transcriptText!.isEmpty
                        
                        if hasTranscript {
                            // Segment has transcript → force to "done" (fixes state desync)
                            segment.status = "done"
                            segment.error = nil
                            session.segments[i] = segment
                            sessionModified = true
                            print("[SessionStore] Fixed segment \(segment.id) from transcribing to done (has transcript)")
                            
                            // Log recovery fix
                            AppLogger.log(AppLogger.STORE, "Recovery fixed session=\(AppLogger.shortId(session.id)) seg=\(segment.index) from=transcribing to=done (has_transcript)")
                        } else {
                            // No transcript → transcription was interrupted, reset to queued
                            segment.status = "queued"
                            segment.error = nil
                            session.segments[i] = segment
                            sessionModified = true
                            print("[SessionStore] Reset segment \(segment.id) from transcribing to queued")
                            
                            // Log recovery update
                            AppLogger.log(AppLogger.STORE, "Recovery updated session=\(AppLogger.shortId(session.id)) seg=\(segment.index) from=transcribing to=queued")
                        }
                    }
                }
                
                // FIX: Finalize stuck "processing" sessions where all segments are terminal.
                // Catches sessions where worker marked segment failed but returned early without finalizing.
                if session.status == "processing" {
                    let hasIncompleteSegments = session.segments.contains {
                        $0.status == "queued" || $0.status == "transcribing"
                    }
                    if !hasIncompleteSegments {
                        session.status = "complete"
                        if session.endedAt == nil { session.endedAt = Date() }
                        if session.finalTranscriptText == nil {
                            session.finalTranscriptText = session.segments
                                .sorted { $0.index < $1.index }
                                .compactMap { $0.transcriptText }
                                .joined(separator: " ")
                        }
                        sessionModified = true
                        let doneCount = session.segments.filter { $0.status == "done" }.count
                        let failedCount = session.segments.filter { $0.status == "failed" }.count
                        print("[SessionStore] Finalized stuck processing session \(session.id) (done=\(doneCount) failed=\(failedCount))")
                        AppLogger.log(AppLogger.STORE, "[RECOVERY] finalized session=\(AppLogger.shortId(session.id)) reason=stuck_processing done=\(doneCount) failed=\(failedCount)")
                    }
                }
                
                // Save the modified session if changes were made
                if sessionModified {
                    do {
                        try saveSession(session)
                        modifiedSessions.append(session)
                        print("[SessionStore] Saved recovered session \(session.id)")
                    } catch {
                        print("[SessionStore] Failed to save recovered session \(session.id): \(error)")
                    }
                }
            }
            
            // Fix "failed" segments with "No speech detected" errors (one-time migration)
            var needsMigration = false
            for i in 0..<session.segments.count {
                var segment = session.segments[i]
                
                if segment.status == "failed" {
                    let isNoSpeechError = segment.error?.contains("No speech detected") ?? false ||
                                          segment.error?.contains("no speech") ?? false
                    
                    if isNoSpeechError {
                        // Mark as done with empty transcript
                        segment.status = "done"
                        segment.transcriptText = ""
                        segment.error = nil
                        session.segments[i] = segment
                        needsMigration = true
                        print("[SessionStore] Migrated 'no speech' segment \(segment.id) from failed to done")
                    }
                }
            }
            
            if needsMigration {
                do {
                    try saveSession(session)
                    modifiedSessions.append(session)
                    print("[SessionStore] Saved migrated session \(session.id)")
                } catch {
                    print("[SessionStore] Failed to save migrated session \(session.id): \(error)")
                }
            }
        }
        
        print("[SessionStore] Recovery complete. Modified \(modifiedSessions.count) sessions")
        
        // Return the full list of sessions (reload to get latest state)
        return loadAllSessions()
    }
}

// MARK: - Error Types

/// Errors that can occur during session storage operations
enum SessionStoreError: LocalizedError {
    case sessionNotFound(String)
    case segmentNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .sessionNotFound(let sessionId):
            return "Session not found: \(sessionId)"
        case .segmentNotFound(let segmentId):
            return "Segment not found: \(segmentId)"
        }
    }
}
