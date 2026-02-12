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
struct Intention: Codable, Identifiable {
    /// Unique identifier (UUID string)
    let id: String
    
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
    let createdAt: Date
    
    init(
        id: String = UUID().uuidString,
        title: String,
        targetValue: Double,
        unit: String,
        timeframe: String,
        category: String? = nil,
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.targetValue = targetValue
        self.unit = unit
        self.timeframe = timeframe
        self.category = category
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
