//
//  DailyMoodStore.swift
//  Attune
//
//  Handles persistence of DailyMood objects to/from JSON files.
//  One file per date: Documents/Attune/DailyMood/<dateKey>.json
//

import Foundation

/// Manages loading and saving of DailyMood objects to disk using JSON.
/// Keyed by dateKey (YYYY-MM-DD); one record per day.
@MainActor
final class DailyMoodStore {
    
    // MARK: - Initialization
    
    /// Shared singleton instance
    static let shared = DailyMoodStore()
    
    private init() {
        try? AppPaths.ensureDirectoriesExist()
    }
    
    // MARK: - Loading
    
    /// Loads mood for a specific date
    /// Returns nil if no record exists for that date
    func loadDailyMood(dateKey: String) -> DailyMood? {
        let fileURL = AppPaths.dailyMoodFileURL(dateKey: dateKey)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DailyMood.self, from: data)
    }
    
    /// Loads mood for today (uses current local date)
    func loadTodayMood() -> DailyMood? {
        loadDailyMood(dateKey: AppPaths.dateKey(from: Date()))
    }
    
    // MARK: - Saving
    
    /// Saves or updates mood for a date (atomic write)
    /// Creates or overwrites the file for that dateKey
    func saveDailyMood(_ mood: DailyMood) throws {
        try AppPaths.ensureDirectoriesExist()
        
        let fileURL = AppPaths.dailyMoodFileURL(dateKey: mood.dateKey)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(mood)
        try data.write(to: fileURL, options: .atomic)
        
        AppLogger.log(AppLogger.STORE, "DailyMood saved dateKey=\(mood.dateKey) moodLabel=\(mood.moodLabel ?? "nil")")
    }
    
    /// Updates or creates mood for a date with extracted values from a check-in.
    /// Skips overwrite if existing mood has isManualOverride == true (latest wins unless user overrode).
    func setMoodFromCheckInIfNotOverridden(dateKey: String, moodLabel: String?, moodScore: Int?, sourceCheckInId: String) throws {
        let existing = loadDailyMood(dateKey: dateKey)
        if existing?.isManualOverride == true {
            return  // Don't overwrite user's manual mood
        }
        try setMoodFromCheckIn(dateKey: dateKey, moodLabel: moodLabel, moodScore: moodScore, sourceCheckInId: sourceCheckInId)
    }
    
    /// Updates or creates mood for a date with extracted values from a check-in (unconditional overwrite)
    func setMoodFromCheckIn(dateKey: String, moodLabel: String?, moodScore: Int?, sourceCheckInId: String) throws {
        let mood = DailyMood(
            dateKey: dateKey,
            moodLabel: moodLabel,
            moodScore: moodScore,
            updatedAt: Date(),
            sourceCheckInId: sourceCheckInId,
            isManualOverride: false
        )
        try saveDailyMood(mood)
    }
    
    /// Clears manual override for a date so GPT can overwrite on next check-in extraction.
    /// Saves record with isManualOverride=false, moodLabel=nil, moodScore=nil.
    func clearManualOverride(dateKey: String) throws {
        let mood = DailyMood(
            dateKey: dateKey,
            moodLabel: nil,
            moodScore: nil,
            updatedAt: Date(),
            sourceCheckInId: nil,
            isManualOverride: false
        )
        try saveDailyMood(mood)
    }
    
    /// Updates or creates mood for a date via manual user override
    func setMoodManual(dateKey: String, moodLabel: String?, moodScore: Int?) throws {
        let mood = DailyMood(
            dateKey: dateKey,
            moodLabel: moodLabel,
            moodScore: moodScore,
            updatedAt: Date(),
            sourceCheckInId: nil,
            isManualOverride: true
        )
        try saveDailyMood(mood)
    }
}
