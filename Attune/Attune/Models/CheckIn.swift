//
//  CheckIn.swift
//  Attune
//
//  Represents a single check-in event (e.g., voice recording transcribed).
//  Links to an IntentionSet and holds transcript for later extraction.
//  Part of the Intentions + Check-ins + Progress data layer (Slice 2).
//

import Foundation

/// A single check-in: transcribed voice input tied to an intention set.
/// Used to derive ProgressEntry values and optionally DailyMood.
struct CheckIn: Codable, Identifiable {
    /// Unique identifier (UUID string)
    let id: String
    
    /// When this check-in was created
    let createdAt: Date
    
    /// ID of the IntentionSet this check-in belongs to
    let intentionSetId: String
    
    /// Transcribed text from the check-in (used for extraction)
    let transcript: String
    
    /// Optional audio file name for later retrieval (e.g., if stored in CheckInAudio/)
    let audioFileName: String?
    
    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        intentionSetId: String,
        transcript: String,
        audioFileName: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.intentionSetId = intentionSetId
        self.transcript = transcript
        self.audioFileName = audioFileName
    }
}
