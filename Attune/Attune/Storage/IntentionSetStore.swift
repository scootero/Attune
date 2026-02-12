//
//  IntentionSetStore.swift
//  Attune
//
//  Handles persistence of IntentionSet objects to/from JSON files.
//  One file per set: Documents/Attune/IntentionSets/<id>.json
//  Current set = the one with endedAt == nil (at most one)
//

import Foundation

/// Manages loading and saving of IntentionSet objects to disk using JSON.
/// Supports creating/loading the "current" set (endedAt == nil).
@MainActor
final class IntentionSetStore {
    
    // MARK: - Initialization
    
    /// Shared singleton instance
    static let shared = IntentionSetStore()
    
    private init() {
        try? AppPaths.ensureDirectoriesExist()
    }
    
    // MARK: - Loading
    
    /// Loads a single intention set by ID
    /// Returns nil if file doesn't exist or decode fails
    func loadIntentionSet(id: String) -> IntentionSet? {
        let fileURL = AppPaths.intentionSetFileURL(intentionSetId: id)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(IntentionSet.self, from: data)
    }
    
    /// Loads the current active intention set (endedAt == nil)
    /// Returns nil if no current set exists
    /// If multiple current sets exist (invalid state), returns most recent by startedAt
    func loadCurrentIntentionSet() -> IntentionSet? {
        let all = loadAllIntentionSets()
        let current = all.filter { $0.endedAt == nil }
        return current.sorted { $0.startedAt > $1.startedAt }.first
    }
    
    /// Loads all intention sets from disk
    /// Returns array sorted by startedAt descending
    func loadAllIntentionSets() -> [IntentionSet] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: AppPaths.intentionSetsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let sets = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> IntentionSet? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(IntentionSet.self, from: data)
            }
        
        return sets.sorted { $0.startedAt > $1.startedAt }
    }
    
    // MARK: - Saving / Creating
    
    /// Saves an intention set to disk (atomic write)
    func saveIntentionSet(_ intentionSet: IntentionSet) throws {
        try AppPaths.ensureDirectoriesExist()
        
        let fileURL = AppPaths.intentionSetFileURL(intentionSetId: intentionSet.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(intentionSet)
        try data.write(to: fileURL, options: .atomic)
        
        AppLogger.log(AppLogger.STORE, "IntentionSet saved id=\(AppLogger.shortId(intentionSet.id)) intentionCount=\(intentionSet.intentionIds.count)")
    }
    
    /// Creates a new current intention set (endedAt == nil) with given intention IDs.
    /// If a current set already exists, ends it first (sets endedAt = now) then creates new one.
    /// Returns the newly created IntentionSet
    func createOrLoadCurrentIntentionSet(intentionIds: [String] = []) throws -> IntentionSet {
        // End any existing current set before creating new one
        if let existing = loadCurrentIntentionSet() {
            // IntentionSet has let properties - create new instance with endedAt set
            let endedSet = IntentionSet(
                id: existing.id,
                startedAt: existing.startedAt,
                endedAt: Date(),
                intentionIds: existing.intentionIds
            )
            try saveIntentionSet(endedSet)
        }
        
        // Create new current set
        let newSet = IntentionSet(
            startedAt: Date(),
            endedAt: nil,
            intentionIds: intentionIds
        )
        try saveIntentionSet(newSet)
        return newSet
    }
    
    /// Returns the current intention set, creating an empty one if none exists.
    /// Use this before recording a check-in to ensure we always have a valid intentionSetId.
    func loadOrCreateCurrentIntentionSet() throws -> IntentionSet {
        if let current = loadCurrentIntentionSet() {
            return current
        }
        // No current set — create empty one (do not end any existing; there is none)
        let newSet = IntentionSet(startedAt: Date(), endedAt: nil, intentionIds: [])
        try saveIntentionSet(newSet)
        return newSet
    }
    
    /// Ends the current intention set by setting endedAt = now
    func endCurrentIntentionSet() throws {
        guard let current = loadCurrentIntentionSet() else { return }
        
        let endedSet = IntentionSet(
            id: current.id,
            startedAt: current.startedAt,
            endedAt: Date(),
            intentionIds: current.intentionIds
        )
        try saveIntentionSet(endedSet)
    }
}
