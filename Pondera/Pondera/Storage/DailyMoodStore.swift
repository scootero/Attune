//
//  DailyMoodStore.swift
//  Pondera
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
        
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let mood = try? decoder.decode(DailyMood.self, from: data),
                  let score = mood.moodScore,
                  (-2...2).contains(score) else { continue }
            
            let converted = Self.legacyMoodScoreTo0_10(score)
            let migratedMood = DailyMood(
                dateKey: mood.dateKey,
                moodLabel: mood.moodLabel,
                moodScore: converted,
                updatedAt: mood.updatedAt,
                observedAt: mood.observedAt,
                source: mood.source,
                sourceCheckInId: mood.sourceCheckInId,
                sourceSessionId: mood.sourceSessionId,
                sourceSegmentId: mood.sourceSegmentId,
                isManualOverride: mood.isManualOverride
            )
            if let encoded = try? encoder.encode(migratedMood) {
                try? encoded.write(to: url, options: .atomic)
                AppLogger.log(AppLogger.STORE, "DailyMood migrated dateKey=\(mood.dateKey) \(score)→\(converted)")
            }
        }
        // The directory has now been scanned. Mark migration complete even if
        // it contained no legacy records so future valid 0...2 scores are not
        // mistaken for the old centered scale.
        UserDefaults.standard.set(true, forKey: Self.migrationKey)
    }
    
    /// Converts legacy -2..+2 score to 0-10 scale.
    nonisolated static func legacyMoodScoreTo0_10(_ legacy: Int) -> Int {
        switch legacy {
        case -2: return 0
        case -1: return 2
        case 0: return 5
        case 1: return 8
        case 2: return 10
        default: return max(0, min(10, legacy))
        }
    }
    
    /// Clamps a current score to 0-10 for storage. Legacy conversion belongs
    /// only in the one-time file migration above because 0...2 are also valid
    /// values on the current scale.
    nonisolated static func clampMoodScore(_ score: Int?) -> Int? {
        guard let s = score else { return nil }
        return max(0, min(10, s))
    }
    
    // MARK: - Loading
    
    /// Loads mood for a specific date
    /// Returns nil if no record exists for that date.
    /// Legacy -2...+2 files are converted by the one-time migration before read.
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
    
    /// Backward-compatible entry point. Manual values are no longer permanent
    /// overrides; the mood with the latest observation time wins.
    func setMoodFromCheckInIfNotOverridden(
        dateKey: String,
        moodLabel: String?,
        moodScore: Int?,
        sourceCheckInId: String,
        observedAt: Date = Date()
    ) throws {
        try setMoodFromCheckIn(
            dateKey: dateKey,
            moodLabel: moodLabel,
            moodScore: moodScore,
            sourceCheckInId: sourceCheckInId,
            observedAt: observedAt
        )
    }
    
    /// Updates a date from Check-In only when this observation is newest.
    /// moodScore is clamped to 0-10.
    func setMoodFromCheckIn(
        dateKey: String,
        moodLabel: String?,
        moodScore: Int?,
        sourceCheckInId: String,
        observedAt: Date = Date()
    ) throws {
        try setMoodIfNewer(
            dateKey: dateKey,
            moodLabel: moodLabel,
            moodScore: moodScore,
            observedAt: observedAt,
            source: .checkIn,
            sourceCheckInId: sourceCheckInId
        )
    }

    /// Applies an extracted Talk it out mood without allowing delayed AI work
    /// to overwrite a mood the user expressed or entered later.
    func setMoodFromTalkItOut(
        dateKey: String,
        moodLabel: String?,
        moodScore: Int?,
        sourceSessionId: String,
        sourceSegmentId: String,
        observedAt: Date
    ) throws {
        try setMoodIfNewer(
            dateKey: dateKey,
            moodLabel: moodLabel,
            moodScore: moodScore,
            observedAt: observedAt,
            source: .talkItOut,
            sourceSessionId: sourceSessionId,
            sourceSegmentId: sourceSegmentId
        )
    }
    
    /// Clears mood for a date. Older delayed extractions remain unable to
    /// resurrect the cleared value; a later Check-In or Talk it out can update it.
    func clearManualOverride(dateKey: String) throws {
        let mood = DailyMood(
            dateKey: dateKey,
            moodLabel: nil,
            moodScore: nil,
            updatedAt: Date(),
            observedAt: Date(),
            sourceCheckInId: nil,
            isManualOverride: false
        )
        try saveDailyMood(mood)
    }
    
    /// Updates or creates mood for a date via manual user override
    /// moodScore is clamped to 0-10.
    func setMoodManual(
        dateKey: String,
        moodLabel: String?,
        moodScore: Int?,
        observedAt: Date = Date()
    ) throws {
        try setMoodIfNewer(
            dateKey: dateKey,
            moodLabel: moodLabel,
            moodScore: moodScore,
            observedAt: observedAt,
            source: .manual
        )
    }

    private func setMoodIfNewer(
        dateKey: String,
        moodLabel: String?,
        moodScore: Int?,
        observedAt: Date,
        source: DailyMoodSource,
        sourceCheckInId: String? = nil,
        sourceSessionId: String? = nil,
        sourceSegmentId: String? = nil
    ) throws {
        let existing = loadDailyMood(dateKey: dateKey)
        guard DailyMoodUpdatePolicy.shouldReplace(existing: existing, observedAt: observedAt) else {
            AppLogger.log(
                AppLogger.STORE,
                "DailyMood skipped older source=\(source.rawValue) dateKey=\(dateKey)"
            )
            return
        }

        let mood = DailyMood(
            dateKey: dateKey,
            moodLabel: moodLabel,
            moodScore: Self.clampMoodScore(moodScore),
            updatedAt: Date(),
            observedAt: observedAt,
            source: source,
            sourceCheckInId: sourceCheckInId,
            sourceSessionId: sourceSessionId,
            sourceSegmentId: sourceSegmentId,
            isManualOverride: source == .manual
        )
        try saveDailyMood(mood)
    }
}
