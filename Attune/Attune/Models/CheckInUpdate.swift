//
//  CheckInUpdate.swift
//  Attune
//
//  Single progress update from GPT check-in extraction.
//  Maps to ProgressEntry when persisted. Part of CheckInExtractorService (Slice 4).
//

import Foundation

/// A single progress update extracted from a check-in transcript.
/// updateType: "INCREMENT" = add to running total; "TOTAL" = absolute value for the period.
struct CheckInUpdate: Codable {
    /// ID of the Intention this update applies to
    let intentionId: String
    
    /// "INCREMENT" or "TOTAL"
    let updateType: String
    
    /// Numeric amount (e.g., 3 for "3 pages")
    let amount: Double
    
    /// Unit of measurement (e.g., "pages", "minutes")
    let unit: String
    
    /// Confidence score 0.0 to 1.0
    let confidence: Double
    
    /// Optional short snippet from transcript as evidence
    let evidence: String?
    
    /// Validates updateType is INCREMENT or TOTAL; returns nil if invalid
    var validatedUpdateType: String? {
        (updateType == "INCREMENT" || updateType == "TOTAL") ? updateType : nil
    }
    
    /// Confidence clamped to 0...1
    var clampedConfidence: Double {
        min(1.0, max(0.0, confidence))
    }
}
