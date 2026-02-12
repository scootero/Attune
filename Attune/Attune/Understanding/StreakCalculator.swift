//
//  StreakCalculator.swift
//  Attune
//
//  Computes streak: consecutive days (from today backwards) where day qualifies.
//  Day qualifies if: overallCompletion >= 0.8 AND (≥1 check-in OR any progress entry).
//  Uses last 30 days max. Slice 5.
//

import Foundation

/// Computes streak from historical data.
struct StreakCalculator {
    
    /// Threshold for "day complete" (80%)
    private static let completionThreshold = 0.8
    
    /// Max days to look back
    private static let maxDaysToCheck = 30
    
    /// Computes streak count: consecutive qualifying days from today backwards.
    /// - Parameters:
    ///   - allIntentionSets: All intention sets (to find which was active on each day)
    ///   - intentionsBySetId: Map of intentionSetId -> [Intention]
    ///   - entriesBySetAndDate: Map of "setId|dateKey" -> [ProgressEntry]
    ///   - checkInsBySetAndDate: Map of "setId|dateKey" -> [CheckIn]
    ///   - overridesByDate: Map of dateKey -> (intentionId -> override amount). Slice 7.
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
        
        for dayOffset in 0..<maxDaysToCheck {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { break }
            let dateKey = AppPaths.dateKey(from: date)
            
            guard let activeSet = intentionSetActive(on: dateKey, from: allIntentionSets) else {
                // No set active on this day — doesn't qualify
                if dayOffset == 0 {
                    return 0
                }
                break
            }
            
            let entriesKey = "\(activeSet.id)|\(dateKey)"
            let checkInsKey = entriesKey
            let entries = entriesBySetAndDate[entriesKey] ?? []
            let checkIns = checkInsBySetAndDate[checkInsKey] ?? []
            
            let hasActivity = !checkIns.isEmpty || !entries.isEmpty
            guard hasActivity else {
                if dayOffset == 0 { return 0 }
                break
            }
            
            let intentions = intentionsBySetId[activeSet.id] ?? []
            let overrides = overridesByDate[dateKey] ?? [:]
            var totalsByIntentionId: [String: Double] = [:]
            for intention in intentions {
                let override = overrides[intention.id]
                let total = totalForIntention(entries: entries, dateKey: dateKey, intentionId: intention.id, intentionSetId: activeSet.id, overrideAmount: override)
                totalsByIntentionId[intention.id] = total
            }
            
            let overall = ProgressCalculator.overallPercentComplete(intentions: intentions, totalsByIntentionId: totalsByIntentionId)
            
            guard overall >= completionThreshold else {
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
