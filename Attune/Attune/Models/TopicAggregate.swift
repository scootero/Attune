//
//  TopicAggregate.swift
//  Attune
//
//  Represents an aggregated topic across multiple sessions and mentions.
//  Topics are identified by canonical keys (from Canonicalizer) and track
//  occurrence counts, categories, and linked item IDs.
//

import Foundation

/// Represents an aggregated topic tracked across multiple sessions
struct TopicAggregate: Codable, Identifiable {
    
    // MARK: - Identity & Display
    
    /// Stable canonical key from Canonicalizer (overwritten fingerprint)
    /// Format: "<topicStem>__<shortHash>" (e.g., "spouse_job_change__a1c9f2")
    let canonicalKey: String
    
    /// Deterministic topic key for reliable grouping (Phase 1)
    /// Format: "primaryCategory|conceptSlug" (e.g., "fitness_health|work_out")
    /// This key is NOT affected by time/frequency qualifiers, enabling
    /// "work out today" and "start working out daily" to group together.
    var topicKey: String?
    
    /// Computed ID for Identifiable conformance
    var id: String { canonicalKey }
    
    /// Stable display title derived from topic stem (frozen on creation)
    /// Example: "spouse_job_change" -> "Spouse Job Change"
    /// This title does NOT update with new AI titles to prevent flickering
    let displayTitle: String
    
    // MARK: - Occurrence Tracking
    
    /// Total number of times this topic has been mentioned across all sessions
    var occurrenceCount: Int
    
    /// ISO8601 timestamp when this topic was first seen
    let firstSeenAtISO: String
    
    /// ISO8601 timestamp when this topic was last mentioned (for ordering)
    var lastSeenAtISO: String
    
    // MARK: - Categories & Items
    
    /// Union of all categories assigned to this topic (sorted, unique)
    /// Categories from all mentions are merged together
    var categories: [String]
    
    /// Array of ExtractedItem IDs that mention this topic
    /// These IDs reference items in per-session extraction files
    var itemIds: [String]
    
    // MARK: - Initialization
    
    /// Creates a new topic aggregate from the first mention
    /// - Parameters:
    ///   - canonicalKey: Stable canonical key from item.fingerprint
    ///   - displayTitle: Human-readable title derived from canonical stem
    ///   - firstSeenAtISO: ISO8601 timestamp of first occurrence
    ///   - categories: Initial categories from first item
    ///   - itemId: ID of the first item mentioning this topic
    ///   - topicKey: Optional deterministic topic key for Phase 1 grouping
    init(
        canonicalKey: String,
        displayTitle: String,
        firstSeenAtISO: String,
        categories: [String],
        itemId: String,
        topicKey: String? = nil
    ) {
        self.canonicalKey = canonicalKey
        self.displayTitle = displayTitle
        self.occurrenceCount = 1
        self.firstSeenAtISO = firstSeenAtISO
        self.lastSeenAtISO = firstSeenAtISO
        self.categories = categories.sorted()
        self.itemIds = [itemId]
        self.topicKey = topicKey
    }
    
    // MARK: - Mutation
    
    /// Updates this topic aggregate with a new mention from an item
    /// Increments count, updates last seen, merges categories, and adds item ID
    /// - Parameters:
    ///   - item: The extracted item mentioning this topic
    mutating func addMention(from item: ExtractedItem) {
        // Increment occurrence count
        occurrenceCount += 1
        
        // Update last seen timestamp
        lastSeenAtISO = item.createdAt
        
        // Merge categories (union, sorted, unique)
        let mergedCategories = Set(categories).union(item.categories)
        categories = Array(mergedCategories).sorted()
        
        // Add item ID (duplicates shouldn't happen, but Set would handle it)
        if !itemIds.contains(item.id) {
            itemIds.append(item.id)
        }
    }
}
