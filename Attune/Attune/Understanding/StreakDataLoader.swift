//
//  StreakDataLoader.swift
//  Attune
//
//  Loads all data needed for streak calculation on a background queue.
//  Prevents main-thread blocking when HomeView refreshes after sheet dismiss.
//  Uses same file I/O logic as stores but runs off main thread (no @MainActor).
//

import Foundation

/// Loads streak-related data from disk on a background queue.
/// Call from UI code; completion is always invoked on the main queue for safe @State updates.
enum StreakDataLoader {

    /// Loads all data needed for streak, computes it on background, delivers result on main.
    /// - Parameter completion: Called on main queue with the computed streak count (0 if load fails).
    static func loadStreakInBackground(completion: @escaping (Int) -> Void) {
        // Run heavy file I/O on a background queue so main thread stays responsive
        DispatchQueue.global(qos: .userInitiated).async {
            let streak = computeStreakOffMainThread()
            // Marshal result back to main for UI update (@State must be updated on main)
            DispatchQueue.main.async {
                completion(streak)
            }
        }
    }

    // MARK: - Private: File I/O (mirrors store logic, runs on background queue)

    /// Performs all file reads and streak calculation. Must run off main thread.
    private static func computeStreakOffMainThread() -> Int {
        // 1. Load all intention sets (reads directory + N JSON files)
        let sets = loadAllIntentionSetsOffMain()
        guard !sets.isEmpty else { return 0 }

        // 2. For each set, load its intentions (N files per set)
        var intentionsBySetId: [String: [Intention]] = [:]
        for set in sets {
            let intentions = loadIntentionsOffMain(ids: set.intentionIds).filter { $0.isActive }
            intentionsBySetId[set.id] = intentions
        }

        // 3. Load all progress entries (can be many files)
        let allEntries = loadAllProgressEntriesOffMain()
        var entriesBySetAndDate: [String: [ProgressEntry]] = [:]
        for entry in allEntries {
            let key = "\(entry.intentionSetId)|\(entry.dateKey)"
            entriesBySetAndDate[key, default: []].append(entry)
        }

        // 4. Load all check-ins
        let allCheckIns = loadAllCheckInsOffMain()
        var checkInsBySetAndDate: [String: [CheckIn]] = [:]
        for checkIn in allCheckIns {
            let dateKey = AppPaths.dateKey(from: checkIn.createdAt)
            let key = "\(checkIn.intentionSetId)|\(dateKey)"
            checkInsBySetAndDate[key, default: []].append(checkIn)
        }

        // 5. Load overrides for last 30 days (30 file reads)
        let calendar = Calendar.current
        var overridesByDate: [String: [String: Double]] = [:]
        for dayOffset in 0..<30 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { break }
            let dateKey = AppPaths.dateKey(from: date)
            overridesByDate[dateKey] = loadOverridesForDateOffMain(dateKey: dateKey)
        }

        // 6. Compute streak (pure calculation, no I/O)
        return StreakCalculator.computeStreak(
            allIntentionSets: sets,
            intentionsBySetId: intentionsBySetId,
            entriesBySetAndDate: entriesBySetAndDate,
            checkInsBySetAndDate: checkInsBySetAndDate,
            overridesByDate: overridesByDate
        )
    }

    /// Reads all IntentionSet JSON files from IntentionSets directory.
    private static func loadAllIntentionSetsOffMain() -> [IntentionSet] {
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

    /// Reads intention JSON files by ID (one file per intention).
    private static func loadIntentionsOffMain(ids: [String]) -> [Intention] {
        ids.compactMap { id -> Intention? in
            let fileURL = AppPaths.intentionFileURL(intentionId: id)
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(Intention.self, from: data)
        }
    }

    /// Reads all ProgressEntry JSON files from ProgressEntries directory.
    private static func loadAllProgressEntriesOffMain() -> [ProgressEntry] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: AppPaths.progressEntriesDir, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> ProgressEntry? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(ProgressEntry.self, from: data)
            }
    }

    /// Reads all CheckIn JSON files from CheckIns directory.
    private static func loadAllCheckInsOffMain() -> [CheckIn] {
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

    /// Reads overrides for a single date (one file per date).
    private static func loadOverridesForDateOffMain(dateKey: String) -> [String: Double] {
        let fileURL = AppPaths.progressOverridesFileURL(dateKey: dateKey)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return [:]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let overrides = (try? decoder.decode([ManualProgressOverride].self, from: data)) ?? []
        return Dictionary(uniqueKeysWithValues: overrides.map { ($0.intentionId, $0.amount) })
    }
}
