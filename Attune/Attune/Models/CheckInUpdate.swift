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
    
    /// Optional local clock time components (24h) for when the update occurred // allows resolving same-day time without absolute timestamp
    let tookPlaceLocalTime: TookPlaceLocalTime? // nil means use createdAt for timing
    
    /// Interpretation of the time reference: explicit clock, just-now, or unspecified // guides resolution to a Date
    let timeInterpretation: String? // accepted values: explicit_time, just_now, unspecified
    
    /// Helper for local time components extracted from LLM output // keeps time parsing structured
    struct TookPlaceLocalTime: Codable { // nested to namespace time fields with context
        let hour24: Int // 0-23 hour component in local time
        let minute: Int // 0-59 minute component in local time
    }
    
    /// Custom initializer providing defaults for new optional time fields // keeps older call sites compiling unchanged
    init(
        intentionId: String,
        updateType: String,
        amount: Double,
        unit: String,
        confidence: Double,
        evidence: String?,
        tookPlaceLocalTime: TookPlaceLocalTime? = nil,
        timeInterpretation: String? = nil
    ) {
        self.intentionId = intentionId // store intention identifier
        self.updateType = updateType // store update type (INCREMENT/TOTAL)
        self.amount = amount // store numeric amount
        self.unit = unit // store measurement unit
        self.confidence = confidence // store confidence score
        self.evidence = evidence // store optional evidence snippet
        self.tookPlaceLocalTime = tookPlaceLocalTime // store optional local time components
        self.timeInterpretation = timeInterpretation // store how time should be interpreted
    }
    
    /// Validates updateType is INCREMENT or TOTAL; returns nil if invalid
    var validatedUpdateType: String? {
        (updateType == "INCREMENT" || updateType == "TOTAL") ? updateType : nil
    }
    
    /// Confidence clamped to 0...1
    var clampedConfidence: Double {
        min(1.0, max(0.0, confidence))
    }
}
