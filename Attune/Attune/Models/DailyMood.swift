//
//  DailyMood.swift
//  Attune
//
//  Simple v1 representation of mood for a single day.
//  Keyed by dateKey (YYYY-MM-DD); one record per day.
//  Part of the Intentions + Check-ins + Progress data layer (Slice 2).
//

import Foundation

/// Mood record for a single day.
/// Stored as one file per date (DailyMood/<dateKey>.json).
struct DailyMood: Codable {
    /// Date key in YYYY-MM-DD format (local date)
    let dateKey: String
    
    /// Optional mood label (e.g., "Calm", "Anxious")
    let moodLabel: String?
    
    /// Optional mood score (e.g., -2 to +2 scale)
    let moodScore: Int?
    
    /// When this record was last updated
    let updatedAt: Date
    
    /// Optional ID of CheckIn that provided this mood (nil if manual override)
    let sourceCheckInId: String?
    
    /// True if user manually set/overrode mood (vs extracted from check-in)
    let isManualOverride: Bool
    
    init(
        dateKey: String,
        moodLabel: String? = nil,
        moodScore: Int? = nil,
        updatedAt: Date = Date(),
        sourceCheckInId: String? = nil,
        isManualOverride: Bool = false
    ) {
        self.dateKey = dateKey
        self.moodLabel = moodLabel
        self.moodScore = moodScore
        self.updatedAt = updatedAt
        self.sourceCheckInId = sourceCheckInId
        self.isManualOverride = isManualOverride
    }
}
