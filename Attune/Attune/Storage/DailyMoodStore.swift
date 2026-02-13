//
//  DailyMoodStore.swift
//  Attune
//
//  Handles persistence of DailyMood objects to/from JSON files.
//  One file per date: Documents/Attune/DailyMood/<dateKey>.json
//  Slice A: moodScore migrated from -2..+2 to 0-10.
//

import Foundation

/// Manages loading and saving of DailyMood objects to disk using JSON.
/// Keyed by dateKey (YYYY-MM-DD); one record per day.
@MainActor
final class DailyMoodStore {
    
    /// UserDefaults key for one-time migration flag (legacy -2..+2 → 0-10)
    private static let migrationKey = "DailyMoodMigratedTo0_10"
    
    // MARK: - Initialization
    
    /// Shared singleton instance
    static let shared = DailyMoodStore()
    
    private init() {
        try? AppPaths.ensureDirectoriesExist()
        migrateLegacyMoodScoresIfNeeded()
    }
    
    // MARK: - Migration (Slice A)
    
    /// One-time migration: convert legacy moodScore -2..+2 to 0-10 and rewrite files.
    /// Mapping: -2→0, -1→2, 0→5, 1→8, 2→10
    private func migrateLegacyMoodScoresIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.migrationKey) else { return }
        
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: AppPaths.dailyMoodDir, includingPropertiesForKeys: nil) else {
            return
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        var migrated = false
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  var mood = try? decoder.decode(DailyMood.self, from: data),
                  let score = mood.moodScore,
                  (-2...2).contains(score) else { continue }
            
            let converted = Self.legacyMoodScoreTo0_10(score)
            let migratedMood = DailyMood(
                dateKey: mood.dateKey,
                moodLabel: mood.moodLabel,
                moodScore: converted,
                updatedAt: mood.updatedAt,
                sourceCheckInId: mood.sourceCheckInId,
                isManualOverride: mood.isManualOverride
            )
            if let encoded = try? encoder.encode(migratedMood) {
                try? encoded.write(to: url, options: .atomic)
                migrated = true
                AppLogger.log(AppLogger.STORE, "DailyMood migrated dateKey=\(mood.dateKey) \(score)→\(converted)")
            }
        }
        if migrated {
            UserDefaults.standard.set(true, forKey: Self.migrationKey)
        }
    }
    
    /// Converts legacy -2..+2 score to 0-10 scale.
    static func legacyMoodScoreTo0_10(_ legacy: Int) -> Int {
        switch legacy {
        case -2: return 0
        case -1: return 2
        case 0: return 5
        case 1: return 8
        case 2: return 10
        default: return max(0, min(10, legacy))
        }
    }
    
    /// Clamps score to 0-10 for storage (call before saving).
    static func clampMoodScore(_ score: Int?) -> Int? {
        guard let s = score else { return nil }
        if (-2...2).contains(s) { return legacyMoodScoreTo0_10(s) }
        return max(0, min(10, s))
    }
    
    // MARK: - Loading
    
    /// Loads mood for a specific date
    /// Returns nil if no record exists for that date.
    /// Any legacy -2..+2 scores are converted to 0-10 on read (after migration).
    func loadDailyMood(dateKey: String) -> DailyMood? {
        let fileURL = AppPaths.dailyMoodFileURL(dateKey: dateKey)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var mood = try? decoder.decode(DailyMood.self, from: data) else { return nil }
        
        if let score = mood.moodScore, (-2...2).contains(score) {
            mood = DailyMood(
                dateKey: mood.dateKey,
                moodLabel: mood.moodLabel,
                moodScore: Self.legacyMoodScoreTo0_10(score),
                updatedAt: mood.updatedAt,
                sourceCheckInId: mood.sourceCheckInId,
                isManualOverride: mood.isManualOverride
            )
        }
        return mood
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
    /// moodScore is clamped to 0-10; legacy -2..+2 values are converted automatically.
    func setMoodFromCheckIn(dateKey: String, moodLabel: String?, moodScore: Int?, sourceCheckInId: String) throws {
        let mood = DailyMood(
            dateKey: dateKey,
            moodLabel: moodLabel,
            moodScore: Self.clampMoodScore(moodScore),
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
    /// moodScore is clamped to 0-10.
    func setMoodManual(dateKey: String, moodLabel: String?, moodScore: Int?) throws {
        let mood = DailyMood(
            dateKey: dateKey,
            moodLabel: moodLabel,
            moodScore: Self.clampMoodScore(moodScore),
            updatedAt: Date(),
            sourceCheckInId: nil,
            isManualOverride: true
        )
        try saveDailyMood(mood)
    }
}
