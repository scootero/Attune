//
//  ExtractedItem.swift
//  Attune
//
//  Represents a candidate item extracted from segment transcripts.
//  Items can be events, intentions, commitments, or states captured from speech.
//

import Foundation

/// Calendar candidate information for potential event scheduling
struct CalendarCandidate: Codable {
    /// Suggested title for the calendar event
    var suggestedTitle: String?
    
    /// ISO8601 formatted start date/time string (e.g., "2026-02-15T14:00:00Z")
    var startISO8601: String?
    
    /// ISO8601 formatted end date/time string (e.g., "2026-02-15T15:00:00Z")
    var endISO8601: String?
    
    /// Whether this is an all-day event
    var isAllDay: Bool?
    
    /// Additional notes or context for the calendar entry
    var notes: String?
}

/// Represents an extracted candidate item from a segment transcript.
/// Each item represents something the user said that might need tracking:
/// events, intentions, commitments, or state observations.
struct ExtractedItem: Codable, Identifiable {
    
    // MARK: - Identity & Linkage
    
    /// Unique identifier for this extracted item
    let id: String
    
    /// Parent session identifier
    let sessionId: String
    
    /// Parent segment identifier
    let segmentId: String
    
    /// Segment index within the session (for display/sorting)
    let segmentIndex: Int
    
    // MARK: - Extraction Content
    
    /// Type of extracted item from approved list: "event", "intention", "commitment", "state"
    /// Unknown values are allowed without crashing for future extensibility
    let type: String
    
    /// Brief title summarizing the extracted item
    let title: String
    
    /// Longer summary providing context and details
    let summary: String
    
    /// Categories from approved list (e.g., "fitness_health", "career_work")
    /// Standard values: "fitness_health", "career_work", "money_finance",
    /// "personal_growth", "relationships_social", "stress_load", "peace_wellbeing"
    /// Unknown values are allowed without crashing for future extensibility
    let categories: [String]
    
    /// Confidence score from LLM extraction (0.0 to 1.0)
    let confidence: Double
    
    /// Strength/importance score from LLM extraction (0.0 to 1.0)
    let strength: Double
    
    // MARK: - Traceability
    
    /// Exact quote from transcript that led to this extraction
    let sourceQuote: String
    
    /// Optional context from before the source quote
    var contextBefore: String?
    
    /// Optional context from after the source quote
    var contextAfter: String?
    
    // MARK: - Deduplication & Review
    
    /// Fingerprint for deduplication (computed from content hash)
    /// Used to detect and skip duplicate extractions within a session
    let fingerprint: String
    
    /// Review state from approved list: "new", "confirmed", "rejected", "edited"
    /// Unknown values are allowed without crashing for future extensibility
    var reviewState: String
    
    /// ISO8601 formatted timestamp when item was reviewed (optional)
    /// Using String instead of Date for v1 to avoid codec complexity
    var reviewedAt: String?
    
    // MARK: - Optional Calendar Data
    
    /// Optional calendar candidate information if this item is event-like
    var calendarCandidate: CalendarCandidate?
    
    // MARK: - Timestamps
    
    /// ISO8601 formatted timestamp when item was created
    /// Using String instead of Date for v1 to avoid codec complexity and maintain simpler debugging
    let createdAt: String
    
    /// ISO8601 formatted timestamp when extraction was performed
    /// Using String instead of Date for v1 to avoid codec complexity and maintain simpler debugging
    let extractedAt: String
    
    // MARK: - Initialization
    
    /// Creates a new extracted item
    init(
        id: String = UUID().uuidString,
        sessionId: String,
        segmentId: String,
        segmentIndex: Int,
        type: String,
        title: String,
        summary: String,
        categories: [String],
        confidence: Double,
        strength: Double,
        sourceQuote: String,
        contextBefore: String? = nil,
        contextAfter: String? = nil,
        fingerprint: String,
        reviewState: String = "new",
        reviewedAt: String? = nil,
        calendarCandidate: CalendarCandidate? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        extractedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.sessionId = sessionId
        self.segmentId = segmentId
        self.segmentIndex = segmentIndex
        self.type = type
        self.title = title
        self.summary = summary
        self.categories = categories
        self.confidence = confidence
        self.strength = strength
        self.sourceQuote = sourceQuote
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
        self.fingerprint = fingerprint
        self.reviewState = reviewState
        self.reviewedAt = reviewedAt
        self.calendarCandidate = calendarCandidate
        self.createdAt = createdAt
        self.extractedAt = extractedAt
    }
}

// MARK: - Canonical String Constants

extension ExtractedItem {
    /// Standard category identifiers
    /// These are the canonical internal values; UI can map to display labels later
    enum Category {
        static let fitnessHealth = "fitness_health"
        static let careerWork = "career_work"
        static let moneyFinance = "money_finance"
        static let personalGrowth = "personal_growth"
        static let relationshipsSocial = "relationships_social"
        static let stressLoad = "stress_load"
        static let peaceWellbeing = "peace_wellbeing"
    }
    
    /// Standard item types
    enum ItemType {
        static let event = "event"
        static let intention = "intention"
        static let commitment = "commitment"
        static let state = "state"
    }
    
    /// Standard review states
    enum ReviewState {
        static let new = "new"
        static let confirmed = "confirmed"
        static let rejected = "rejected"
        static let edited = "edited"
    }
}

// MARK: - Corrections Overlay

extension ExtractedItem {
    /// Applies user corrections as an overlay on top of AI values
    /// Original AI values are never mutated; corrections are applied at read time
    /// - Parameter correction: Optional correction to apply (if nil, returns original values)
    /// - Returns: View model with corrected or original values
    func applyingCorrection(_ correction: ItemCorrection?) -> CorrectedItemView {
        guard let correction = correction else {
            // No correction exists - return original AI values
            return CorrectedItemView(
                item: self,
                displayTitle: self.title,
                displayType: self.type,
                displayCategories: self.categories,
                isMarkedIncorrect: false,
                correctionNote: nil
            )
        }
        
        // Apply corrections overlay
        return CorrectedItemView(
            item: self,
            displayTitle: correction.correctedTitle ?? self.title,
            displayType: correction.correctedType ?? self.type,
            displayCategories: correction.correctedCategories ?? self.categories,
            isMarkedIncorrect: correction.isIncorrect,
            correctionNote: correction.note
        )
    }
}

/// View model representing an ExtractedItem with corrections applied
/// This is the display layer that UI should use instead of reading raw ExtractedItem fields
struct CorrectedItemView {
    /// Original item (for accessing immutable fields like sourceQuote, timestamps, etc.)
    let item: ExtractedItem
    
    /// Display title (corrected or original)
    let displayTitle: String
    
    /// Display type (corrected or original)
    let displayType: String
    
    /// Display categories (corrected or original)
    let displayCategories: [String]
    
    /// Whether user marked this item as incorrect
    let isMarkedIncorrect: Bool
    
    /// Optional correction note from user
    let correctionNote: String?
}
