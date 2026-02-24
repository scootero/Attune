//
//  MomentumPoint.swift
//  Attune
//
//  Single data point for Momentum detail chart: % accomplished per intention
//  at a check-in timestamp. Can exceed 100% (bonus progress).
//

import Foundation

/// One bar in the Momentum chart: intention's % at a specific check-in time.
struct MomentumPoint: Identifiable {

    /// Stable ID for SwiftUI ForEach (checkInId + intentionId)
    let id: String

    /// Check-in timestamp (used for X-axis placement)
    let date: Date

    /// Intention this point belongs to
    let intentionId: String

    /// Intention title for legend
    let intentionTitle: String

    /// Color index for palette lookup (or use intentionId for stable mapping)
    let colorIndex: Int

    /// Recording/check-in identifier when available (used to keep bars from the same recording grouped together visually)
    let recordingId: String?

    /// Percent accomplished (0–100+; can exceed 100 for "bonus" display)
    let percent: Double

    /// Optional: small time offset in seconds for overlapping bars at same x.
    /// Used when multiple intentions share a timestamp (largest bar gets larger offset).
    let timeOffsetSeconds: Double

    init(
        id: String,
        date: Date,
        intentionId: String,
        intentionTitle: String,
        colorIndex: Int,
        recordingId: String? = nil,
        percent: Double,
        timeOffsetSeconds: Double = 0
    ) {
        self.id = id
        self.date = date
        self.intentionId = intentionId
        self.intentionTitle = intentionTitle
        self.colorIndex = colorIndex
        self.recordingId = recordingId
        self.percent = percent
        self.timeOffsetSeconds = timeOffsetSeconds
    }
}
