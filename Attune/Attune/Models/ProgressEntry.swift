//
//  ProgressEntry.swift
//  Attune
//
//  Represents a single progress update toward an intention (e.g., "read 3 pages").
//  Derived from CheckIn transcript extraction.
//  Part of the Intentions + Check-ins + Progress data layer (Slice 2).
//

import Foundation

/// A single progress update for an intention.
/// updateType: "INCREMENT" = add to running total, "TOTAL" = absolute value for the period
struct ProgressEntry: Codable, Identifiable {
    /// Unique identifier (UUID string)
    let id: String
    
    /// When this entry was created
    let createdAt: Date
    
    /// Date key in YYYY-MM-DD format (local date for grouping)
    let dateKey: String
    
    /// ID of the IntentionSet this entry belongs to
    let intentionSetId: String
    
    /// ID of the specific Intention this entry applies to
    let intentionId: String
    
    /// "INCREMENT" = add amount to running total; "TOTAL" = absolute value for date/timeframe
    let updateType: String
    
    /// Numeric amount (e.g., 3 for "3 pages")
    let amount: Double
    
    /// Unit of measurement (e.g., "pages", "minutes")
    let unit: String
    
    /// Confidence score for this extraction (0.0 to 1.0)
    let confidence: Double
    
    /// Optional snippet from transcript that provided evidence for this entry
    let evidence: String?
    
    /// ID of the CheckIn that produced this entry
    let sourceCheckInId: String
    
    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        dateKey: String,
        intentionSetId: String,
        intentionId: String,
        updateType: String,
        amount: Double,
        unit: String,
        confidence: Double,
        evidence: String? = nil,
        sourceCheckInId: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.dateKey = dateKey
        self.intentionSetId = intentionSetId
        self.intentionId = intentionId
        self.updateType = updateType
        self.amount = amount
        self.unit = unit
        self.confidence = confidence
        self.evidence = evidence
        self.sourceCheckInId = sourceCheckInId
    }
}
