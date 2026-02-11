//
//  Session.swift
//  Attune
//
//  Represents a recording session containing one or more audio segments.
//

import Foundation

/// Represents a single recording session with its segments and metadata.
/// Each session can contain multiple segments recorded at fixed intervals.
struct Session: Codable, Identifiable {
    /// Unique identifier for this session
    let id: String
    
    /// When the recording session started
    let startedAt: Date
    
    /// When the recording session ended (nil if still in progress)
    var endedAt: Date?
    
    /// Current status of the session
    /// Possible values: "recording", "stopping", "processing", "complete", "error"
    var status: String
    
    /// Duration of each segment in seconds (default: 300)
    let segmentDurationSec: Int
    
    /// All segments belonging to this session
    var segments: [Segment]
    
    /// Last error message if status is "error"
    var lastError: String?
    
    /// Full session transcript (derived from concatenated segment transcripts)
    /// Computed after all segments are transcribed when session is marked complete
    var finalTranscriptText: String?
    
    /// Creates a new session
    init(
        id: String = UUID().uuidString,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        status: String = "recording",
        segmentDurationSec: Int = 300,
        segments: [Segment] = [],
        lastError: String? = nil,
        finalTranscriptText: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.segmentDurationSec = segmentDurationSec
        self.segments = segments
        self.lastError = lastError
        self.finalTranscriptText = finalTranscriptText
    }
}

// MARK: - Session Helpers

extension Session {
    /// Returns a short ID (first 6 characters) for display purposes
    var shortId: String {
        String(id.prefix(6))
    }
    
    /// Returns formatted duration string if session has ended
    /// Format: HH:mm:ss for sessions >= 1 hour, mm:ss for shorter sessions
    var durationFormatted: String? {
        guard let endedAt = endedAt else { return nil }
        let interval = endedAt.timeIntervalSince(startedAt)
        
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval < 3600 ? [.minute, .second] : [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .pad
        
        return formatter.string(from: interval)
    }
    
    /// Builds a joined transcript from all segments, ordered by index
    /// Missing or empty transcripts are replaced with placeholder text
    func joinedTranscript() -> String {
        let sortedSegments = segments.sorted { $0.index < $1.index }
        
        let transcriptParts = sortedSegments.map { segment in
            if let text = segment.transcriptText, !text.isEmpty {
                return text
            } else {
                return "[Missing transcript for segment \(segment.index)]"
            }
        }
        
        return transcriptParts.joined(separator: "\n\n")
    }
}
