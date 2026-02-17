//
//  ProgressCalculator.swift
//  Attune
//
//  Pure functions for computing progress totals and % complete.
//  TOTAL overwrite rule: if any TOTAL exists for day/intention, use it; else sum INCREMENT.
//  Slice 4.
//

import Foundation

/// Computes progress totals and percent-complete from ProgressEntry data.
/// All functions are pure (take data as input; no store dependency).
struct ProgressCalculator {
    
    /// Returns YYYY-MM-DD for local date (delegates to AppPaths)
    static func dateKey(for date: Date) -> String {
        AppPaths.dateKey(from: date)
    }
    
    /// Total for an intention on a given date.
    /// Override precedence (Slice 7): If overrideAmount provided, return it. Else use entry-based logic.
    /// Entry rule: If any TOTAL exists, use latest. Else sum INCREMENTs.
    /// - Parameter overrideAmount: Optional manual override (takes precedence over entries)
    static func totalForIntention(entries: [ProgressEntry], dateKey: String, intentionId: String, intentionSetId: String, overrideAmount: Double? = nil) -> Double {
        if let override = overrideAmount {
            return override
        }
        
        let filtered = entries.filter {
            $0.dateKey == dateKey && $0.intentionId == intentionId && $0.intentionSetId == intentionSetId
        }
        
        // Check for any TOTAL (latest wins)
        let totals = filtered.filter { $0.updateType == "TOTAL" }
            .sorted { $0.createdAt > $1.createdAt }
        
        if let latestTotal = totals.first {
            return latestTotal.amount
        }
        
        // Else sum INCREMENTs
        return filtered
            .filter { $0.updateType == "INCREMENT" }
            .reduce(0) { $0 + $1.amount }
    }
    
    /// Percent complete for a single intention.
    /// Daily: clamp(total / targetValue, 0...1)
    /// Weekly: expectedPerDay = targetValue / 7, then clamp(total / expectedPerDay, 0...1) for today's progress
    /// - Parameter targetValue: Must be > 0 (returns 0 if targetValue <= 0)
    static func percentComplete(total: Double, targetValue: Double, timeframe: String) -> Double {
        guard targetValue > 0 else { return 0 }
        
        let effectiveTarget: Double
        if timeframe.lowercased() == "weekly" {
            effectiveTarget = targetValue / 7.0
        } else {
            effectiveTarget = targetValue
        }
        
        return min(1.0, max(0.0, total / effectiveTarget))
    }
    
    /// Cumulative INCREMENT amount for an intention on a given date, up to and including entries at or before a given timestamp.
    /// Used by Check-In Detail to show "Total today" percent. Only sums INCREMENT entries (TOTAL entries ignored).
    /// Entries are sorted by createdAt ascending before summing to ensure correct chronological order.
    /// - Parameters:
    ///   - entries: All progress entries (caller filters by dateKey/intentionId/intentionSetId, or passes day's entries)
    ///   - dateKey: YYYY-MM-DD for the day
    ///   - intentionId: The intention/metric
    ///   - intentionSetId: The intention set
    ///   - atOrBeforeCreatedAt: Only include entries whose createdAt <= this date
    /// - Returns: Sum of INCREMENT amounts for matching entries
    static func cumulativeIncrementAmountUpTo(
        entries: [ProgressEntry],
        dateKey: String,
        intentionId: String,
        intentionSetId: String,
        atOrBeforeCreatedAt: Date
    ) -> Double {
        // Match same day, same intention, INCREMENT only, and createdAt at or before cutoff
        let filtered = entries
            .filter {
                $0.dateKey == dateKey
                && $0.intentionId == intentionId
                && $0.intentionSetId == intentionSetId
                && $0.updateType == "INCREMENT"
                && $0.createdAt <= atOrBeforeCreatedAt
            }
        // Sort ascending so we sum in chronological order (defensive if caller passes unsorted data)
        let sorted = filtered.sorted { $0.createdAt < $1.createdAt }
        return sorted.reduce(0) { $0 + $1.amount }
    }
    
    /// Overall percent complete: average of per-intention %Complete across active intentions with targetValue > 0.
    /// Ignores intentions with targetValue <= 0.
    /// - Parameters:
    ///   - intentions: Active intentions
    ///   - totalsByIntentionId: Map of intentionId -> computed total for today
    static func overallPercentComplete(intentions: [Intention], totalsByIntentionId: [String: Double]) -> Double {
        let eligible = intentions.filter { $0.isActive && $0.targetValue > 0 }
        guard !eligible.isEmpty else { return 0 }
        
        let sum = eligible.reduce(0.0) { acc, intention in
            let total = totalsByIntentionId[intention.id] ?? 0
            let pct = percentComplete(total: total, targetValue: intention.targetValue, timeframe: intention.timeframe)
            return acc + pct
        }
        
        return sum / Double(eligible.count)
    }
}
