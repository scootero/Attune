//
//  StreakCalculator.swift
//  Attune
//
//  Computes streak: consecutive days (from today backwards) where day qualifies.
//  Day qualifies if: at least one check-in was recorded that calendar day.
//  Uses local calendar (user timezone). Multiple check-ins in one day count as 1 day.
//  Uses last 30 days max. Slice 5.
//

import Foundation

/// Computes streak from historical data.
struct StreakCalculator {
    
    /// Max days to look back
    private static let maxDaysToCheck = 30
    
    /// Computes streak count: consecutive qualifying days from today backwards.
    /// Qualification: at least one check-in on that calendar day (same as Home page "recorded check-in").
    /// - Parameters:
    ///   - allIntentionSets: All intention sets (kept for API compatibility; no longer used for qualification)
    ///   - intentionsBySetId: Map of intentionSetId -> [Intention] (kept for API compatibility)
    ///   - entriesBySetAndDate: Map of "setId|dateKey" -> [ProgressEntry] (kept for API compatibility)
    ///   - checkInsBySetAndDate: Map of "setId|dateKey" -> [CheckIn]
    ///   - overridesByDate: Map of dateKey -> (intentionId -> override amount) (kept for API compatibility)
    /// - Returns: Number of consecutive qualifying days (0 if today doesn't qualify)
    static func computeStreak(
        allIntentionSets: [IntentionSet],
        intentionsBySetId: [String: [Intention]],
        entriesBySetAndDate: [String: [ProgressEntry]],
        checkInsBySetAndDate: [String: [CheckIn]],
        overridesByDate: [String: [String: Double]] = [:]
    ) -> Int {
        let calendar = Calendar.current
        var streak = 0
        
        // Build set of dateKeys that have at least one check-in (any intention set)
        var dateKeysWithCheckIns: Set<String> = []
        for (key, checkIns) in checkInsBySetAndDate where !checkIns.isEmpty {
            // Key format: "setId|dateKey"
            if let pipeIndex = key.firstIndex(of: "|") {
                let dateKey = String(key[key.index(after: pipeIndex)...])
                dateKeysWithCheckIns.insert(dateKey)
            }
        }
        
        for dayOffset in 0..<maxDaysToCheck {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { break }
            let dateKey = AppPaths.dateKey(from: date)
            
            // Day qualifies if it has at least one check-in (same definition as Home "recorded check-in")
            guard dateKeysWithCheckIns.contains(dateKey) else {
                if dayOffset == 0 { return 0 }
                break
            }
            
            streak += 1
        }
        
        return streak
    }
    
    /// Finds the intention set that was active on a given date.
    /// Public for reuse by Progress tab (DayDetail, etc.). Set active if startedAt <= endOfDay and (endedAt == nil or > startOfDay).
    static func intentionSetActive(on dateKey: String, from sets: [IntentionSet]) -> IntentionSet? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        guard let date = formatter.date(from: dateKey) else { return nil }
        
        let startOfDay = calendarStartOfDay(date)
        let endOfDay = calendarEndOfDay(date)
        
        for set in sets {
            let startedBeforeOrOn = set.startedAt <= endOfDay
            // Set still active at start of day (endedAt nil or after day started)
            let notEndedBefore = set.endedAt == nil || set.endedAt! > startOfDay
            if startedBeforeOrOn && notEndedBefore {
                return set
            }
        }
        return nil
    }
    
    private static var calendar: Calendar { Calendar.current }
    
    private static func calendarStartOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }
    
    private static func calendarEndOfDay(_ date: Date) -> Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return calendar.date(byAdding: components, to: calendarStartOfDay(date)) ?? date
    }
    
    private static func totalForIntention(entries: [ProgressEntry], dateKey: String, intentionId: String, intentionSetId: String, overrideAmount: Double? = nil) -> Double {
        ProgressCalculator.totalForIntention(
            entries: entries,
            dateKey: dateKey,
            intentionId: intentionId,
            intentionSetId: intentionSetId,
            overrideAmount: overrideAmount
        )
    }
}
