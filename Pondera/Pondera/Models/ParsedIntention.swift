// ParsedIntention.swift // explains the file purpose for clarity
// Attune // keeps project context consistent
// Lightweight DTO returned by the IntentionsParserService for voice-derived intentions // states why this type exists
import Foundation // needed for String and Double types

/// ParsedIntention represents a single intention parsed from a transcript before persistence. // documents the struct role
struct ParsedIntention { // defines the container for parsed intention fields
    let title: String // required human-readable intention title
    let target: Double? // optional numeric target; defaults applied later when nil
    let unit: String? // optional unit text; defaults applied later when nil
    let category: String? // optional category aligned with existing category strings
    let notes: String? // optional notes for future use or display
}

/// Helper to convert a parsed intention into a DraftIntention for the edit form. // explains purpose of extension
extension ParsedIntention { // scopes conversion helper to ParsedIntention
    func toDraftIntention() -> DraftIntention { // maps parsed data into editable draft row
        DraftIntention( // initializes a new draft intention
            id: UUID().uuidString, // generate a fresh identifier so it can be saved later
            title: title.trimmingCharacters(in: .whitespacesAndNewlines), // trim to avoid stray spaces from transcript
            targetValue: max(0, target ?? 1), // default missing targets to 1 and clamp to non-negative
            unit: (unit?.isEmpty == false ? unit! : "times"), // default missing or empty units to times
            timeframe: "daily" // default timeframe per plan (daily) until user edits
        ) // end initializer
    } // end function
} // end extension
