//
//  ProgressStore.swift
//  Attune
//
//  Handles persistence of ProgressEntry objects to/from JSON files.
//  One file per entry: Documents/Attune/ProgressEntries/<id>.json
//  Supports reading by dateKey + intentionSetId for UI queries.
//

import Foundation

/// Manages loading and saving of ProgressEntry objects to disk using JSON.
/// Supports appending entries and querying by date + intention set.
@MainActor
final class ProgressStore {
    
    // MARK: - Initialization
    
    /// Shared singleton instance
    static let shared = ProgressStore()
    
    private init() {
        try? AppPaths.ensureDirectoriesExist()
    }
    
    // MARK: - Loading
    
    /// Loads a single progress entry by ID
    func loadProgressEntry(id: String) -> ProgressEntry? {
        let fileURL = AppPaths.progressEntryFileURL(entryId: id)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ProgressEntry.self, from: data)
    }
    
    /// Loads all progress entries for a given dateKey and intentionSetId
    /// Returns array sorted by createdAt ascending
    func loadEntries(dateKey: String, intentionSetId: String) -> [ProgressEntry] {
        let all = loadAllProgressEntries()
        return all
            .filter { $0.dateKey == dateKey && $0.intentionSetId == intentionSetId }
            .sorted { $0.createdAt < $1.createdAt }
    }
    
    /// Loads all progress entries for an intention set (any date)
    /// Returns array sorted by dateKey desc, then createdAt asc
    func loadEntries(intentionSetId: String) -> [ProgressEntry] {
        let all = loadAllProgressEntries()
        return all
            .filter { $0.intentionSetId == intentionSetId }
            .sorted { a, b in
                if a.dateKey != b.dateKey { return a.dateKey > b.dateKey }
                return a.createdAt < b.createdAt
            }
    }
    
    /// Loads all progress entries from disk
    func loadAllProgressEntries() -> [ProgressEntry] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: AppPaths.progressEntriesDir, includingPropertiesForKeys: nil) else {
            return []
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let entries = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> ProgressEntry? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(ProgressEntry.self, from: data)
            }
        
        return entries
    }
    
    // MARK: - Saving / Appending
    
    /// Saves a progress entry to disk (atomic write)
    func saveProgressEntry(_ entry: ProgressEntry) throws {
        try AppPaths.ensureDirectoriesExist()
        
        let fileURL = AppPaths.progressEntryFileURL(entryId: entry.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(entry)
        try data.write(to: fileURL, options: .atomic)
        
        AppLogger.log(AppLogger.STORE, "ProgressEntry saved id=\(AppLogger.shortId(entry.id)) dateKey=\(entry.dateKey) intentionId=\(AppLogger.shortId(entry.intentionId))")
    }
    
    /// Appends a new progress entry (creates and saves)
    /// Returns the newly created ProgressEntry
    func appendProgressEntry(
        dateKey: String,
        intentionSetId: String,
        intentionId: String,
        updateType: String,
        amount: Double,
        unit: String,
        confidence: Double,
        evidence: String? = nil,
        sourceCheckInId: String,
        tookPlaceAt: Date? = nil // optional explicit occurrence time; nil keeps legacy behavior via fallback
    ) throws -> ProgressEntry {
        let entry = ProgressEntry(
            tookPlaceAt: tookPlaceAt, // pass through explicit occurrence time so model can compute effectiveTookPlaceAt (must precede dateKey in initializer)
            dateKey: dateKey,
            intentionSetId: intentionSetId,
            intentionId: intentionId,
            updateType: updateType,
            amount: amount,
            unit: unit,
            confidence: confidence,
            evidence: evidence,
            sourceCheckInId: sourceCheckInId
        )
        try saveProgressEntry(entry)
        return entry
    }
}
