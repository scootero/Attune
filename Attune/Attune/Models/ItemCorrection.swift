//
//  ItemCorrection.swift
//  Attune
//
//  Represents user corrections to extracted items.
//  Corrections are overlaid on items at display time and when building topic aggregates.
//  Original AI values are never deleted; corrections are applied as an overlay.
//

import Foundation

/// Represents a user correction to an extracted item
/// Corrections are keyed by itemId (ExtractedItem.id.uuidString) and stored separately
/// from per-session extraction files to avoid retroactive mutation.
struct ItemCorrection: Codable, Identifiable {
    
    // MARK: - Identity
    
    /// Item ID from ExtractedItem.id.uuidString
    /// This links the correction to a specific extracted item across sessions
    let itemId: String
    
    /// Computed ID for Identifiable conformance
    var id: String { itemId }
    
    // MARK: - Correction Flags
    
    /// Whether the user marked this item as incorrect
    /// If true, the item may be dimmed/hidden in UI or excluded from aggregates
    var isIncorrect: Bool
    
    // MARK: - Corrected Fields (optional overrides)
    
    /// User-corrected title (overrides ExtractedItem.title if present)
    var correctedTitle: String?
    
    /// User-corrected type (overrides ExtractedItem.type if present)
    /// Should be one of: "event", "intention", "commitment", "state"
    var correctedType: String?
    
    /// User-corrected categories (overrides ExtractedItem.categories if present)
    /// Should contain values from ExtractedItem.Category constants
    var correctedCategories: [String]?
    
    /// Optional user note explaining the correction
    var note: String?
    
    // MARK: - Timestamps
    
    /// ISO8601 timestamp when correction was last updated
    var updatedAtISO: String
    
    // MARK: - Initialization
    
    /// Creates a new item correction
    /// - Parameters:
    ///   - itemId: Item ID from ExtractedItem.id.uuidString
    ///   - isIncorrect: Whether the item is marked incorrect (default: false)
    ///   - correctedTitle: Optional corrected title
    ///   - correctedType: Optional corrected type
    ///   - correctedCategories: Optional corrected categories
    ///   - note: Optional user note
    ///   - updatedAtISO: ISO8601 timestamp (defaults to now)
    init(
        itemId: String,
        isIncorrect: Bool = false,
        correctedTitle: String? = nil,
        correctedType: String? = nil,
        correctedCategories: [String]? = nil,
        note: String? = nil,
        updatedAtISO: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.itemId = itemId
        self.isIncorrect = isIncorrect
        self.correctedTitle = correctedTitle
        self.correctedType = correctedType
        self.correctedCategories = correctedCategories
        self.note = note
        self.updatedAtISO = updatedAtISO
    }
}
