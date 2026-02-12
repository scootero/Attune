//
//  AmbiguityChecker.swift
//  Attune
//
//  Slice 7: Determines when a check-in update is ambiguous and should trigger
//  the disambiguation prompt. Uses late-day hour, confidence band, and
//  materially-change threshold.
//

import Foundation

/// Slice 7 constants for ambiguity disambiguation
struct AmbiguityChecker {
    /// Hour (0–23) at which "late day" starts. Check-ins at or after this hour may trigger.
    static let lateDayStartHour = 18
    
    /// Minimum change as fraction of target (e.g. 0.20 = 20%) to be "material"
    static let materiallyChangePct = 0.20
    
    /// Confidence band: updates with confidence in [min, max] are considered ambiguous
    static let confidenceBandMin = 0.45
    static let confidenceBandMax = 0.80
    
    /// Returns true if the update should trigger the disambiguation prompt.
    /// All conditions must be true: late-day, confidence in band, material change.
    /// - Parameters:
    ///   - update: The extracted progress update
    ///   - currentTotal: Current total for that intention today (including overrides)
    ///   - targetValue: Target value for the intention (must be > 0)
    ///   - checkInCreatedAt: When the check-in was created (for late-day check)
    static func isAmbiguous(
        update: CheckInUpdate,
        currentTotal: Double,
        targetValue: Double,
        checkInCreatedAt: Date
    ) -> Bool {
        // 1) Late-day: hour >= lateDayStartHour (local time)
        let hour = Calendar.current.component(.hour, from: checkInCreatedAt)
        guard hour >= lateDayStartHour else { return false }
        
        // 2) Confidence in ambiguous band [0.45, 0.80]
        let conf = update.clampedConfidence
        guard conf >= confidenceBandMin && conf <= confidenceBandMax else { return false }
        
        // 3) Material change: |newTotal - currentTotal| / targetValue >= 0.20
        guard targetValue > 0 else { return false }
        let newTotal: Double
        switch update.updateType {
        case "TOTAL":
            newTotal = update.amount
        case "INCREMENT":
            newTotal = currentTotal + update.amount
        default:
            return false
        }
        let changePct = abs(newTotal - currentTotal) / targetValue
        guard changePct >= materiallyChangePct else { return false }
        
        return true
    }
}
