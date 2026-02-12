//
//  CheckInStore.swift
//  Attune
//
//  Handles persistence of CheckIn objects to/from JSON files.
//  One file per check-in: Documents/Attune/CheckIns/<id>.json
//

import Foundation

/// Manages loading and saving of CheckIn objects to disk using JSON.
/// Supports appending new check-ins (each saved as its own file).
@MainActor
final class CheckInStore {
    
    // MARK: - Initialization
    
    /// Shared singleton instance
    static let shared = CheckInStore()
    
    private init() {
        try? AppPaths.ensureDirectoriesExist()
    }
    
    // MARK: - Loading
    
    /// Loads a single check-in by ID
    func loadCheckIn(id: String) -> CheckIn? {
        let fileURL = AppPaths.checkInFileURL(checkInId: id)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CheckIn.self, from: data)
    }
    
    /// Loads check-ins for an intention set on a specific date (dateKey YYYY-MM-DD)
    func loadCheckIns(intentionSetId: String, dateKey: String) -> [CheckIn] {
        let all = loadCheckIns(intentionSetId: intentionSetId)
        return all.filter { AppPaths.dateKey(from: $0.createdAt) == dateKey }
    }
    
    /// Loads all check-ins for a specific intention set
    /// Returns array sorted by createdAt ascending (chronological)
    func loadCheckIns(intentionSetId: String) -> [CheckIn] {
        let all = loadAllCheckIns()
        return all
            .filter { $0.intentionSetId == intentionSetId }
            .sorted { $0.createdAt < $1.createdAt }
    }
    
    /// Loads all check-ins from disk
    /// Returns array sorted by createdAt descending
    func loadAllCheckIns() -> [CheckIn] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: AppPaths.checkInsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let checkIns = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> CheckIn? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(CheckIn.self, from: data)
            }
        
        return checkIns.sorted { $0.createdAt > $1.createdAt }
    }
    
    // MARK: - Saving / Appending
    
    /// Saves a check-in to disk (atomic write)
    /// Use this to "append" a new check-in (each is stored as separate file)
    func saveCheckIn(_ checkIn: CheckIn) throws {
        try AppPaths.ensureDirectoriesExist()
        
        let fileURL = AppPaths.checkInFileURL(checkInId: checkIn.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(checkIn)
        try data.write(to: fileURL, options: .atomic)
        
        AppLogger.log(AppLogger.STORE, "CheckIn saved id=\(AppLogger.shortId(checkIn.id)) intentionSetId=\(AppLogger.shortId(checkIn.intentionSetId))")
    }
    
    /// Appends a new check-in (creates and saves)
    /// Returns the newly created CheckIn
    func appendCheckIn(intentionSetId: String, transcript: String, audioFileName: String? = nil) throws -> CheckIn {
        let checkIn = CheckIn(
            intentionSetId: intentionSetId,
            transcript: transcript,
            audioFileName: audioFileName
        )
        try saveCheckIn(checkIn)
        return checkIn
    }
}
