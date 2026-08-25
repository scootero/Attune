//
//  WeekMomentum.swift
//  Pondera
//
//  Models for weekly momentum visualization (Mon–Sun).
//  Used by HomeView Weekly Momentum section. Slice A.
//

import Foundation

/// Tier for coloring momentum bars (red→orange→grey→green gradient).
enum MomentumTier: String {
    case veryLow
    case low
    case neutral
    case good
    case great
}

/// Momentum data for a single day in the current week.
struct DayMomentum: Identifiable {
    /// The date (local midnight or start-of-day)
    let date: Date
    
    /// Single letter for day: M T W T F S S
    let weekdayLetter: String
    
    /// Completion ratio 0.0–1.0; nil for future days (UI shows empty bar).
    let completionRatio: Double?
    
    /// Tier derived from completionRatio for bar coloring.
    let tier: MomentumTier
    
    /// True if this day is after today (hasn't occurred yet).
    let isFutureDay: Bool
    
    /// True if there are intentions with progress data for this day.
    let hasData: Bool

    /// False before the user had an active intention to track. These days are
    /// neutral context, not missed days.
    let isTrackingEligible: Bool

    init(
        date: Date,
        weekdayLetter: String,
        completionRatio: Double?,
        tier: MomentumTier,
        isFutureDay: Bool,
        hasData: Bool,
        isTrackingEligible: Bool = true
    ) {
        self.date = date
        self.weekdayLetter = weekdayLetter
        self.completionRatio = completionRatio
        self.tier = tier
        self.isFutureDay = isFutureDay
        self.hasData = hasData
        self.isTrackingEligible = isTrackingEligible
    }
    
    var id: Date { date }
}

/// Week momentum for current calendar week (Mon–Sun).
struct WeekMomentum {
    /// Always 7 elements, Mon through Sun.
    let days: [DayMomentum]
}
