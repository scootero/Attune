//
//  ManualProgressOverride.swift
//  Attune
//
//  User override of computed progress total for an intention on a date.
//  Override takes precedence over ProgressEntry-computed total. Slice 7.
//

import Foundation

/// Manual override for an intention's total on a specific date.
/// Scope: (dateKey, intentionId) — applies regardless of IntentionSet.
struct ManualProgressOverride: Codable {
    /// Date key YYYY-MM-DD
    let dateKey: String
    
    /// Intention ID
    let intentionId: String
    
    /// Override amount (replaces computed total)
    let amount: Double
    
    /// Unit for display (e.g., "pages", "minutes")
    let unit: String
    
    /// When the override was set
    let updatedAt: Date
    
    init(
        dateKey: String,
        intentionId: String,
        amount: Double,
        unit: String,
        updatedAt: Date = Date()
    ) {
        self.dateKey = dateKey
        self.intentionId = intentionId
        self.amount = amount
        self.unit = unit
        self.updatedAt = updatedAt
    }
}
