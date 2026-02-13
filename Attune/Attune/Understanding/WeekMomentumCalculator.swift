//
//  WeekMomentumCalculator.swift
//  Attune
//
//  Computes WeekMomentum for the current calendar week (Mon–Sun).
//  Uses real intention + progress data. Future days show empty (no bar).
//  Slice A.
//

import Foundation

/// Computes weekly momentum for HomeView.
struct WeekMomentumCalculator {
    
    /// Computes WeekMomentum for the current calendar week.
    /// - Parameters:
    ///   - today: Current date (local); used to detect future days.
    ///   - intentionSet: Current IntentionSet (used for all 7 days).
    ///   - intentions: Active intentions from the set.
    ///   - entriesForDate: Returns ProgressEntry array for given dateKey + intentionSetId.
    ///   - overridesForDate: Returns override amounts [intentionId: Double] for given dateKey.
    static func compute(
        today: Date,
        intentionSet: IntentionSet,
        intentions: [Intention],
        entriesForDate: (String) -> [ProgressEntry],
        overridesForDate: (String) -> [String: Double]
    ) -> WeekMomentum {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: today)
        
        // Monday of current week: weekday 1=Sun, 2=Mon, ... so daysFromMonday = (weekday+5)%7
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        guard let mondayDate = calendar.date(byAdding: .day, value: -daysFromMonday, to: startOfToday) else {
            return WeekMomentum(days: [])
        }
        
        var days: [DayMomentum] = []
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: mondayDate) else { continue }
            let dateKey = ProgressCalculator.dateKey(for: date)
            let weekdayLetter = WeekMomentumCalculator.weekdayLetters[offset]
            
            if date > startOfToday {
                days.append(DayMomentum(
                    date: date,
                    weekdayLetter: weekdayLetter,
                    completionRatio: nil,
                    tier: .neutral,
                    isFutureDay: true,
                    hasData: false
                ))
                continue
            }
            
            let entries = entriesForDate(dateKey)
            let overrides = overridesForDate(dateKey)
            let activeIntentions = intentions.filter { $0.isActive }
            let n = activeIntentions.count
            
            if n == 0 {
                days.append(DayMomentum(
                    date: date,
                    weekdayLetter: weekdayLetter,
                    completionRatio: 0,
                    tier: .veryLow,
                    isFutureDay: false,
                    hasData: false
                ))
                continue
            }
            
            var sum: Double = 0
            for intention in activeIntentions {
                let total = ProgressCalculator.totalForIntention(
                    entries: entries,
                    dateKey: dateKey,
                    intentionId: intention.id,
                    intentionSetId: intentionSet.id,
                    overrideAmount: overrides[intention.id]
                )
                let percent = ProgressCalculator.percentComplete(
                    total: total,
                    targetValue: intention.targetValue,
                    timeframe: intention.timeframe
                )
                let value: Double
                if percent >= 1.0 { value = 1.0 }
                else if percent > 0 { value = 0.5 }
                else { value = 0.0 }
                sum += value
            }
            
            let ratio = sum / Double(max(n, 1))
            let tier = tierFromCompletionRatio(ratio)
            days.append(DayMomentum(
                date: date,
                weekdayLetter: weekdayLetter,
                completionRatio: ratio,
                tier: tier,
                isFutureDay: false,
                hasData: true
            ))
        }
        
        return WeekMomentum(days: days)
    }
    
}

extension WeekMomentumCalculator {
    
    fileprivate static let weekdayLetters = ["M", "T", "W", "T", "F", "S", "S"]
    
    fileprivate static func tierFromCompletionRatio(_ ratio: Double) -> MomentumTier {
        switch ratio {
        case ..<0.25: return .veryLow
        case 0.25..<0.5: return .low
        case 0.5..<0.75: return .neutral
        case 0.75..<1.0: return .good
        default: return .great
        }
    }
}
