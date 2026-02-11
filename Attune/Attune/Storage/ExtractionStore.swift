//
//  ExtractionStore.swift
//  Attune
//
//  Handles persistence of ExtractedItem objects to/from JSON files.
//  Each session has its own extraction file containing an array of items.
//

import Foundation

/// Result of appending items, indicating how many were added vs skipped due to deduplication
struct AppendResult {
    let added: Int
    let skipped: Int
}

/// Manages loading and saving of ExtractedItem objects to disk using JSON.
/// Each session's extractions are stored as a separate JSON array in the Extractions directory.
/// File format: [ExtractedItem] (bare array, no wrapper)
@MainActor
final class ExtractionStore {
    
    // MARK: - Initialization
    
    /// Shared singleton instance
    static let shared = ExtractionStore()
    
    private init() {
        // Ensure directories exist on initialization
        try? AppPaths.ensureDirectoriesExist()
    }
    
    // MARK: - Loading
    
    /// Loads all extracted items for a specific session
    /// Returns an array of items, or empty array if file doesn't exist or decode fails
    /// - Parameter sessionId: The ID of the session to load extractions for
    /// - Returns: Array of extracted items for this session
    func loadExtractions(sessionId: String) -> [ExtractedItem] {
        let fileURL = AppPaths.extractionFileURL(sessionId: sessionId)
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        
        // Load and decode
        guard let data = try? Data(contentsOf: fileURL) else {
            AppLogger.log(AppLogger.ERR, "Extractions load failed session=\(AppLogger.shortId(sessionId)) error=\"Failed to read file\"")
            return []
        }
        
        // Configure decoder (dates are strings, so default strategy is fine)
        let decoder = JSONDecoder()
        
        guard let items = try? decoder.decode([ExtractedItem].self, from: data) else {
            AppLogger.log(AppLogger.ERR, "Extractions decode failed session=\(AppLogger.shortId(sessionId)) error=\"JSON decode error\"")
            return []
        }
        
        return items
    }
    
    /// Loads all extracted items from all sessions
    /// Returns a flattened array of all items, sorted by createdAt descending (most recent first)
    /// - Returns: Array of all extracted items across all sessions
    func loadAllExtractions() -> [ExtractedItem] {
        let fileManager = FileManager.default
        
        // Get all extraction files
        guard let files = try? fileManager.contentsOfDirectory(at: AppPaths.extractionsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        
        // Load each file and flatten into single array
        var allItems: [ExtractedItem] = []
        
        for fileURL in files.filter({ $0.pathExtension == "json" }) {
            guard let data = try? Data(contentsOf: fileURL) else {
                continue
            }
            
            let decoder = JSONDecoder()
            
            if let items = try? decoder.decode([ExtractedItem].self, from: data) {
                allItems.append(contentsOf: items)
            } else {
                // Log decode failure but continue processing other files
                let filename = fileURL.lastPathComponent
                AppLogger.log(AppLogger.ERR, "Extractions decode failed file=\(filename)")
            }
        }
        
        // Sort by createdAt descending (string comparison works for ISO8601)
        return allItems.sorted { $0.createdAt > $1.createdAt }
    }
    
    /// Loads extracted items for a specific segment within a session
    /// Filters by segmentId for precise matching
    /// - Parameters:
    ///   - sessionId: The session containing the segment
    ///   - segmentId: The unique segment identifier
    /// - Returns: Array of items extracted from this specific segment
    func loadExtractions(sessionId: String, segmentId: String) -> [ExtractedItem] {
        let allItems = loadExtractions(sessionId: sessionId)
        return allItems.filter { $0.segmentId == segmentId }
    }
    
    /// Loads extracted items for a specific segment within a session by index
    /// Filters by segmentIndex (useful for UI display and debugging)
    /// - Parameters:
    ///   - sessionId: The session containing the segment
    ///   - segmentIndex: The zero-based segment index
    /// - Returns: Array of items extracted from the segment at this index
    func loadExtractions(sessionId: String, segmentIndex: Int) -> [ExtractedItem] {
        let allItems = loadExtractions(sessionId: sessionId)
        return allItems.filter { $0.segmentIndex == segmentIndex }
    }
    
    // MARK: - Saving
    
    /// Appends new items to a session's extraction file with deduplication
    /// Dedupe rule: Skip items whose fingerprint already exists in the file OR in the batch
    /// - Parameters:
    ///   - sessionId: The ID of the session to append to
    ///   - items: Array of items to append
    /// - Returns: Result indicating how many items were added vs skipped
    func appendItems(sessionId: String, items: [ExtractedItem]) -> AppendResult {
        // Load existing items for this session
        var existingItems = loadExtractions(sessionId: sessionId)
        
        // Build set of existing fingerprints
        var seenFingerprints = Set(existingItems.map { $0.fingerprint })
        
        var added = 0
        var skipped = 0
        
        // Process each item, checking for duplicates both in file and within batch
        for item in items {
            if seenFingerprints.contains(item.fingerprint) {
                skipped += 1
            } else {
                existingItems.append(item)
                seenFingerprints.insert(item.fingerprint)
                added += 1
            }
        }
        
        // Save updated items array (only if we added something)
        if added > 0 {
            do {
                try saveExtractions(sessionId: sessionId, items: existingItems)
                AppLogger.log(AppLogger.STORE, "Extractions saved session=\(AppLogger.shortId(sessionId)) added=\(added) skipped=\(skipped)")
            } catch {
                AppLogger.log(AppLogger.ERR, "Extractions save failed session=\(AppLogger.shortId(sessionId)) error=\"\(error.localizedDescription)\"")
                // Return what we attempted (caller can decide how to handle failure)
            }
        } else if skipped > 0 {
            // All items were duplicates, log this
            AppLogger.log(AppLogger.STORE, "Extractions unchanged session=\(AppLogger.shortId(sessionId)) skipped=\(skipped) (all duplicates)")
        }
        
        return AppendResult(added: added, skipped: skipped)
    }
    
    /// Updates an existing item in a session's extraction file
    /// Replaces the item with matching ID and persists the updated array
    /// - Parameters:
    ///   - sessionId: The ID of the session containing the item
    ///   - item: The updated item (must have existing ID)
    /// - Returns: true if item was found and updated, false if not found
    func updateItem(sessionId: String, item: ExtractedItem) -> Bool {
        var items = loadExtractions(sessionId: sessionId)
        
        // Find item by ID
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            AppLogger.log(AppLogger.ERR, "Extractions update failed session=\(AppLogger.shortId(sessionId)) item=\(AppLogger.shortId(item.id)) error=\"Item not found\"")
            return false
        }
        
        // Replace item
        items[index] = item
        
        // Save updated array
        do {
            try saveExtractions(sessionId: sessionId, items: items)
            AppLogger.log(AppLogger.STORE, "Extractions updated session=\(AppLogger.shortId(sessionId)) item=\(AppLogger.shortId(item.id))")
            return true
        } catch {
            AppLogger.log(AppLogger.ERR, "Extractions update save failed session=\(AppLogger.shortId(sessionId)) item=\(AppLogger.shortId(item.id)) error=\"\(error.localizedDescription)\"")
            return false
        }
    }
    
    // MARK: - Private Helpers
    
    /// Saves an array of items to a session's extraction file (atomic write)
    /// - Parameters:
    ///   - sessionId: The ID of the session
    ///   - items: Array of items to persist
    private func saveExtractions(sessionId: String, items: [ExtractedItem]) throws {
        let fileURL = AppPaths.extractionFileURL(sessionId: sessionId)
        
        // Encode items to JSON with pretty printing for readability
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(items)
        
        // Atomic write to prevent corruption
        try data.write(to: fileURL, options: .atomic)
    }
}
