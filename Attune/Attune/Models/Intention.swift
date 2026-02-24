//
//  Intention.swift
//  Attune
//
//  Represents a user-defined intention/goal for tracking (e.g., "read 10 pages daily").
//  Part of the Intentions + Check-ins + Progress data layer (Slice 2).
//

import Foundation

/// A single intention or goal the user wants to track toward.
/// Examples: "Read 10 pages daily", "Exercise 30 minutes weekly"
struct Intention: Codable, Identifiable { // Conforms to Codable for persistence and Identifiable for UI binding
    /// Unique identifier (UUID string)
    let id: String // Stored intention ID
    
    /// Human-readable title for the intention (e.g., "Read more")
    let title: String
    
    /// Target value to reach (e.g., 10 for "10 pages")
    let targetValue: Double
    
    /// Unit of measurement (e.g., "pages", "minutes", "sessions")
    let unit: String
    
    /// Timeframe for the intention: "daily" or "weekly"
    let timeframe: String
    
    /// Optional category for grouping (e.g., "fitness", "reading")
    let category: String?
    
    /// Whether this intention is currently active (inactive = archived, not shown in current set)
    let isActive: Bool
    
    /// When this intention was created
    let createdAt: Date // Timestamp when intention was created

    /// Optional aliases/synonyms to help mapping (e.g., "run", "weights" for "Workout")
    let aliases: [String] // Allows semantic matches without changing the title
    
    init(
        id: String = UUID().uuidString,
        title: String,
        targetValue: Double,
        unit: String,
        timeframe: String,
        category: String? = nil,
        isActive: Bool = true,
        createdAt: Date = Date(),
        aliases: [String] = []
    ) {
        self.id = id // Persist provided or generated ID
        self.title = title // Store human-readable title
        self.targetValue = targetValue // Store numeric target for tracking
        self.unit = unit // Store measurement unit
        self.timeframe = timeframe // Store timeframe (daily/weekly)
        self.category = category // Store optional grouping category
        self.isActive = isActive // Store active/archived state
        self.createdAt = createdAt // Store creation timestamp
        self.aliases = aliases // Store provided aliases or default to empty
    }

    private enum CodingKeys: String, CodingKey { // Define coding keys for custom decode/encode
        case id // Coding key for id
        case title // Coding key for title
        case targetValue // Coding key for targetValue
        case unit // Coding key for unit
        case timeframe // Coding key for timeframe
        case category // Coding key for category
        case isActive // Coding key for isActive
        case createdAt // Coding key for createdAt
        case aliases // Coding key for aliases
    }

    init(from decoder: Decoder) throws { // Custom decoder to supply default aliases when missing
        let container = try decoder.container(keyedBy: CodingKeys.self) // Decode keyed container
        id = try container.decode(String.self, forKey: .id) // Decode id
        title = try container.decode(String.self, forKey: .title) // Decode title
        targetValue = try container.decode(Double.self, forKey: .targetValue) // Decode targetValue
        unit = try container.decode(String.self, forKey: .unit) // Decode unit
        timeframe = try container.decode(String.self, forKey: .timeframe) // Decode timeframe
        category = try container.decodeIfPresent(String.self, forKey: .category) // Decode optional category
        isActive = try container.decode(Bool.self, forKey: .isActive) // Decode isActive
        createdAt = try container.decode(Date.self, forKey: .createdAt) // Decode createdAt
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? [] // Decode aliases or default to empty for backward compatibility
    }

    func encode(to encoder: Encoder) throws { // Custom encoder to include aliases
        var container = encoder.container(keyedBy: CodingKeys.self) // Create keyed container
        try container.encode(id, forKey: .id) // Encode id
        try container.encode(title, forKey: .title) // Encode title
        try container.encode(targetValue, forKey: .targetValue) // Encode targetValue
        try container.encode(unit, forKey: .unit) // Encode unit
        try container.encode(timeframe, forKey: .timeframe) // Encode timeframe
        try container.encode(category, forKey: .category) // Encode category (handles nil)
        try container.encode(isActive, forKey: .isActive) // Encode isActive
        try container.encode(createdAt, forKey: .createdAt) // Encode createdAt
        try container.encode(aliases, forKey: .aliases) // Encode aliases (empty array serialized)
    }
}
