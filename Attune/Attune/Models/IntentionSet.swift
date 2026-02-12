//
//  IntentionSet.swift
//  Attune
//
//  Represents a span of time during which a set of intentions is active.
//  endedAt == nil means this is the current active set.
//  Part of the Intentions + Check-ins + Progress data layer (Slice 2).
//

import Foundation

/// A set of intentions active during a time span.
/// There is typically one "current" set (endedAt == nil) at a time.
struct IntentionSet: Codable, Identifiable {
    /// Unique identifier (UUID string)
    let id: String
    
    /// When this intention set became active
    let startedAt: Date
    
    /// When this set ended (nil = still the current active set)
    let endedAt: Date?
    
    /// IDs of intentions belonging to this set (references Intention.id)
    let intentionIds: [String]
    
    init(
        id: String = UUID().uuidString,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        intentionIds: [String] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.intentionIds = intentionIds
    }
}
