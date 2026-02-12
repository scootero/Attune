//
//  OverrideStore.swift
//  Attune
//
//  Persists ManualProgressOverride. One file per date: ProgressOverrides/<dateKey>.json
//  Override wins over computed total. Slice 7.
//

import Foundation

/// Manages manual progress overrides. One JSON file per date.
@MainActor
final class OverrideStore {
    
    static let shared = OverrideStore()
    
    private init() {
        try? AppPaths.ensureDirectoriesExist()
    }
    
    /// Loads override for a specific date and intention, if any
    func loadOverride(dateKey: String, intentionId: String) -> ManualProgressOverride? {
        let overrides = loadOverridesArray(dateKey: dateKey)
        return overrides.first { $0.intentionId == intentionId }
    }
    
    /// Loads all overrides for a date as intentionId -> amount for fast lookup
    func loadOverridesForDate(dateKey: String) -> [String: Double] {
        let overrides = loadOverridesArray(dateKey: dateKey)
        return Dictionary(uniqueKeysWithValues: overrides.map { ($0.intentionId, $0.amount) })
    }
    
    /// Loads override objects for a date
    private func loadOverridesArray(dateKey: String) -> [ManualProgressOverride] {
        let fileURL = AppPaths.progressOverridesFileURL(dateKey: dateKey)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ManualProgressOverride].self, from: data)) ?? []
    }
    
    /// Saves or updates override for date + intention
    func setOverride(_ override: ManualProgressOverride) throws {
        try AppPaths.ensureDirectoriesExist()
        
        var overrides = loadOverridesArray(dateKey: override.dateKey)
        if let idx = overrides.firstIndex(where: { $0.intentionId == override.intentionId }) {
            overrides[idx] = override
        } else {
            overrides.append(override)
        }
        
        let fileURL = AppPaths.progressOverridesFileURL(dateKey: override.dateKey)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(overrides)
        try data.write(to: fileURL, options: .atomic)
        
        AppLogger.log(AppLogger.STORE, "Override saved dateKey=\(override.dateKey) intentionId=\(AppLogger.shortId(override.intentionId)) amount=\(override.amount)")
    }
    
    /// Clears override for date + intention
    func clearOverride(dateKey: String, intentionId: String) throws {
        var overrides = loadOverridesArray(dateKey: dateKey)
        overrides.removeAll { $0.intentionId == intentionId }
        
        let fileURL = AppPaths.progressOverridesFileURL(dateKey: dateKey)
        if overrides.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
        } else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(overrides)
            try data.write(to: fileURL, options: .atomic)
        }
        
        AppLogger.log(AppLogger.STORE, "Override cleared dateKey=\(dateKey) intentionId=\(AppLogger.shortId(intentionId))")
    }
}
