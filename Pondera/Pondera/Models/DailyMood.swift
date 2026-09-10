//
//  DailyMood.swift
//  Pondera
//
//  Simple v1 representation of mood for a single day.
//  Keyed by dateKey (YYYY-MM-DD); one record per day.
//  Part of the Intentions + Check-ins + Progress data layer (Slice 2).
//

import Foundation

enum DailyMoodSource: String, Codable {
    case manual
    case checkIn = "check_in"
    case talkItOut = "talk_it_out"
}

/// Mood record for a single day.
/// Stored as one file per date (DailyMood/<dateKey>.json).
struct DailyMood: Codable {
    /// Date key in YYYY-MM-DD format (local date)
    let dateKey: String
    
    /// Optional mood label (e.g., "Calm", "Anxious")
    let moodLabel: String?
    
    /// Optional mood score (0–10 integer; 0 = lowest, 10 = highest).
    /// Legacy: values in -2..+2 are migrated to 0-10 on load.
    let moodScore: Int?
    
    /// When this record was last updated
    let updatedAt: Date

    /// When the user expressed or manually entered this mood. This is the
    /// ordering timestamp; `updatedAt` may be later because AI work is async.
    let observedAt: Date?

    /// Where the current daily mood came from.
    let source: DailyMoodSource?
    
    /// Optional ID of CheckIn that provided this mood (nil if manual override)
    let sourceCheckInId: String?

    /// Optional Talk it out provenance for an extracted mood.
    let sourceSessionId: String?
    let sourceSegmentId: String?
    
    /// True if the current value was manually entered rather than extracted.
    let isManualOverride: Bool
    
    init(
        dateKey: String,
        moodLabel: String? = nil,
        moodScore: Int? = nil,
        updatedAt: Date = Date(),
        observedAt: Date? = nil,
        source: DailyMoodSource? = nil,
        sourceCheckInId: String? = nil,
        sourceSessionId: String? = nil,
        sourceSegmentId: String? = nil,
        isManualOverride: Bool = false
    ) {
        self.dateKey = dateKey
        self.moodLabel = moodLabel
        self.moodScore = moodScore
        self.updatedAt = updatedAt
        self.observedAt = observedAt
        self.source = source
        self.sourceCheckInId = sourceCheckInId
        self.sourceSessionId = sourceSessionId
        self.sourceSegmentId = sourceSegmentId
        self.isManualOverride = isManualOverride
    }

    /// Older files predate `observedAt`; their write time is the safest
    /// available ordering signal.
    var effectiveObservedAt: Date { observedAt ?? updatedAt }
}

enum DailyMoodUpdatePolicy {
    static func shouldReplace(existing: DailyMood?, observedAt: Date) -> Bool {
        guard let existing else { return true }
        return observedAt >= existing.effectiveObservedAt
    }
}
