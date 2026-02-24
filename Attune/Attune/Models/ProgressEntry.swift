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
    
    /// Optional explicit time the progress actually took place (nil = use createdAt) // allows storing user-stated clock time without breaking old entries
    let tookPlaceAt: Date? // optional explicit occurrence time; nil means fall back to createdAt
    
    /// Effective time used for chronology; defaults to createdAt when tookPlaceAt is nil // ensures charts and ordering always have a reliable timestamp
    var effectiveTookPlaceAt: Date { // computed property to centralize fallback logic
        tookPlaceAt ?? createdAt // prefer tookPlaceAt if set, else use createdAt for backward compatibility
    }
    
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
        createdAt: Date = Date(), // default to now so old call sites remain valid
        tookPlaceAt: Date? = nil, // optional parameter; nil keeps behavior unchanged unless explicit time provided
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
        self.createdAt = createdAt // store creation time for legacy and fallback behavior
        self.tookPlaceAt = tookPlaceAt // persist explicit occurrence time when provided (else nil)
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
