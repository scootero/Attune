//
//  Segment.swift
//  Attune
//
//  Represents a single audio chunk and its transcription status within a Session.
//

import Foundation

/// Represents a single segment of audio within a recording session.
/// Each segment corresponds to one audio file and its associated transcription.
struct Segment: Codable, Identifiable {
    /// Unique identifier for this segment
    let id: String
    
    /// Parent session identifier
    let sessionId: String
    
    /// Zero-based index within the session's segment array
    let index: Int
    
    /// When this segment started recording
    let startedAt: Date
    
    /// When this segment finished recording (nil if still recording)
    var endedAt: Date?
    
    /// Relative filename for the audio file (e.g., "segment_0.m4a")
    /// Actual path is constructed using AppPaths.audioDir(sessionId:)
    let audioFileName: String
    
    /// Current processing status of this segment
    /// Possible values: "writing", "queued", "transcribing", "done", "failed"
    var status: String
    
    /// Transcribed text from the audio (nil until transcription completes)
    var transcriptText: String?
    
    /// Error message if status is "failed"
    var error: String?
    
    /// Timestamp when audio file was deleted (for cleanup tracking)
    var audioDeletedAt: Date?
    
    /// Creates a new segment
    init(
        id: String = UUID().uuidString,
        sessionId: String,
        index: Int,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        audioFileName: String,
        status: String = "writing",
        transcriptText: String? = nil,
        error: String? = nil,
        audioDeletedAt: Date? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.index = index
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.audioFileName = audioFileName
        self.status = status
        self.transcriptText = transcriptText
        self.error = error
        self.audioDeletedAt = audioDeletedAt
    }
}

// MARK: - Segment Helpers

extension Segment {
    /// Returns a short ID (first 6 characters) for display purposes
    var shortId: String {
        String(id.prefix(6))
    }
}
