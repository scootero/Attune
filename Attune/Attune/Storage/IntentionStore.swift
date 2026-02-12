//
//  IntentionStore.swift
//  Attune
//
//  Handles persistence of Intention objects to/from JSON files.
//  One file per intention: Documents/Attune/Intentions/<id>.json
//

import Foundation

/// Manages loading and saving of Intention objects to disk using JSON.
/// Each intention is stored as a separate JSON file in the Intentions directory.
@MainActor
final class IntentionStore {
    
    // MARK: - Initialization
    
    /// Shared singleton instance
    static let shared = IntentionStore()
    
    private init() {
        try? AppPaths.ensureDirectoriesExist()
    }
    
    // MARK: - Loading
    
    /// Loads a single intention by ID
    /// Returns nil if file doesn't exist or decode fails
    func loadIntention(id: String) -> Intention? {
        let fileURL = AppPaths.intentionFileURL(intentionId: id)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Intention.self, from: data)
    }
    
    /// Loads multiple intentions by IDs (skips missing/invalid)
    /// Returns array in same order as requested IDs; missing items are omitted
    func loadIntentions(ids: [String]) -> [Intention] {
        ids.compactMap { loadIntention(id: $0) }
    }
    
    /// Loads all intentions from disk
    /// Returns array sorted by createdAt descending
    func loadAllIntentions() -> [Intention] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: AppPaths.intentionsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let intentions = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Intention? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Intention.self, from: data)
            }
        
        return intentions.sorted { $0.createdAt > $1.createdAt }
    }
    
    // MARK: - Saving
    
    /// Saves an intention to disk (atomic write)
    func saveIntention(_ intention: Intention) throws {
        try AppPaths.ensureDirectoriesExist()
        
        let fileURL = AppPaths.intentionFileURL(intentionId: intention.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(intention)
        try data.write(to: fileURL, options: .atomic)
        
        AppLogger.log(AppLogger.STORE, "Intention saved id=\(AppLogger.shortId(intention.id)) title=\(intention.title)")
    }
    
    /// Deletes an intention file from disk
    func deleteIntention(id: String) throws {
        let fileURL = AppPaths.intentionFileURL(intentionId: id)
        try FileManager.default.removeItem(at: fileURL)
    }
}
