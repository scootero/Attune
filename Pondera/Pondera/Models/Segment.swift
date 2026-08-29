//
//  Segment.swift
//  Pondera
//
//  Represents a single audio chunk and its transcription status within a Session.
//

import Foundation

/// Time-aligned transcript span from speech recognition.
/// Confidence comes from Apple's speech recognizer when available.
struct TranscriptSpan: Codable, Identifiable {
    let id: String
    let text: String
    let startTime: TimeInterval
    let duration: TimeInterval
    let confidence: Double
    let trust: String

    init(
        id: String = UUID().uuidString,
        text: String,
        startTime: TimeInterval,
        duration: TimeInterval,
        confidence: Double,
        trust: String
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.duration = duration
        self.confidence = confidence
        self.trust = trust
    }
}

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

    /// Trusted portion of the transcript, excluding low-confidence spans.
    /// Extraction uses this text instead of transcriptText when present.
    var trustedTranscriptText: String?

    /// Time-aligned spans used to make transcript quality visible and auditable.
    var transcriptSpans: [TranscriptSpan]?

    /// Average recognizer confidence across spans, 0.0...1.0.
    var transcriptConfidence: Double?

    /// Segment transcript quality: "trusted", "mixed", "lowTrust", or "silent".
    var transcriptQuality: String?

    /// Machine-readable reasons supporting transcriptQuality.
    var transcriptQualityReasons: [String]?
    
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
        trustedTranscriptText: String? = nil,
        transcriptSpans: [TranscriptSpan]? = nil,
        transcriptConfidence: Double? = nil,
        transcriptQuality: String? = nil,
        transcriptQualityReasons: [String]? = nil,
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
        self.trustedTranscriptText = trustedTranscriptText
        self.transcriptSpans = transcriptSpans
        self.transcriptConfidence = transcriptConfidence
        self.transcriptQuality = transcriptQuality
        self.transcriptQualityReasons = transcriptQualityReasons
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

    var extractionTranscriptText: String {
        let trusted = trustedTranscriptText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trusted.isEmpty {
            return trusted
        }
        if transcriptQuality == "lowTrust" || transcriptQuality == "silent" {
            return ""
        }
        return transcriptText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var shouldAllowExtraction: Bool {
        guard status == "done" else { return false }
        guard !extractionTranscriptText.isEmpty else { return false }
        return transcriptQuality != "lowTrust" && transcriptQuality != "silent"
    }
}
