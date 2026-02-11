//
//  CorrectionsStore.swift
//  Attune
//
//  Manages persistence of ItemCorrection objects to/from a single JSON file.
//  Corrections are indexed by itemId for efficient lookups and updates.
//  Corrections are applied as an overlay at display time and when building topic aggregates.
//

import Foundation

/// Manages loading and saving of ItemCorrection objects to disk using JSON.
/// All corrections are stored in a single file: Documents/Attune/Corrections.json
/// File format: [ItemCorrection] (array, for simplicity)
@MainActor
final class CorrectionsStore {
    
    // MARK: - Initialization
    
    /// Shared singleton instance
    static let shared = CorrectionsStore()
    
    private init() {
        // Ensure directories exist on initialization
        try? AppPaths.ensureDirectoriesExist()
    }
    
    // MARK: - Loading
    
    /// Loads all corrections from disk
    /// Returns dictionary indexed by itemId for efficient lookups
    /// - Returns: Dictionary mapping item IDs to corrections
    func loadCorrections() -> [String: ItemCorrection] {
        let fileURL = AppPaths.correctionsFileURL
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        
        // Load and decode
        guard let data = try? Data(contentsOf: fileURL) else {
            AppLogger.log(AppLogger.ERR, "Corrections load failed error=\"Failed to read file\"")
            return [:]
        }
        
        // Configure decoder
        let decoder = JSONDecoder()
        
        guard let correctionsArray = try? decoder.decode([ItemCorrection].self, from: data) else {
            AppLogger.log(AppLogger.ERR, "Corrections decode failed - file may be corrupted")
            return [:]
        }
        
        // Convert array to dictionary for efficient lookups
        var correctionsDict: [String: ItemCorrection] = [:]
        for correction in correctionsArray {
            correctionsDict[correction.itemId] = correction
        }
        
        return correctionsDict
    }
    
    /// Gets a correction for a specific item ID
    /// - Parameter itemId: Item ID (ExtractedItem.id.uuidString)
    /// - Returns: Correction if it exists, nil otherwise
    func getCorrection(itemId: String) -> ItemCorrection? {
        let corrections = loadCorrections()
        return corrections[itemId]
    }
    
    // MARK: - Saving
    
    /// Saves or updates a correction
    /// - Parameter correction: The correction to save
    func setCorrection(_ correction: ItemCorrection) throws {
        // Load existing corrections
        var corrections = loadCorrections()
        
        // Update or insert
        corrections[correction.itemId] = correction
        
        // Save to disk
        try saveCorrections(corrections)
        
        AppLogger.log(
            AppLogger.STORE,
            "Correction saved itemId=\(AppLogger.shortId(correction.itemId)) isIncorrect=\(correction.isIncorrect)"
        )
    }
    
    /// Deletes a correction for a specific item ID
    /// - Parameter itemId: Item ID to remove correction for
    func deleteCorrection(itemId: String) throws {
        var corrections = loadCorrections()
        
        guard corrections[itemId] != nil else {
            // No correction exists, nothing to delete
            return
        }
        
        corrections.removeValue(forKey: itemId)
        
        try saveCorrections(corrections)
        
        AppLogger.log(
            AppLogger.STORE,
            "Correction deleted itemId=\(AppLogger.shortId(itemId))"
        )
    }
    
    // MARK: - Private Helpers
    
    /// Saves corrections dictionary to disk as JSON array
    /// - Parameter corrections: Dictionary of corrections indexed by item ID
    private func saveCorrections(_ corrections: [String: ItemCorrection]) throws {
        let fileURL = AppPaths.correctionsFileURL
        
        // Convert dictionary to array for persistence
        let correctionsArray = Array(corrections.values)
        
        // Encode to JSON with pretty printing for readability
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(correctionsArray)
        
        // Atomic write to prevent corruption
        try data.write(to: fileURL, options: .atomic)
    }
}
