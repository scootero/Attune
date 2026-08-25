//
//  MomentumDemoDataManager.swift
//  Pondera
//
//  Simulator-only Momentum demo data with an explicit, auditable cleanup contract.
//

import CryptoKit
import Foundation

/// Summary shown by the debug Settings UI after a load or cleanup operation.
struct MomentumDemoOperationResult {
    let message: String
}

/// Lightweight status for the simulator-only Settings controls.
struct MomentumDemoStatus {
    let hasDemoData: Bool
    let message: String
}

/// Creates realistic historical CheckIn and ProgressEntry records while reusing the
/// user's existing intentions. The user's Intention JSON files and current
/// IntentionSet JSON file are never edited by this manager.
///
/// IMPORTANT CLEANUP CONTRACT — read before changing or removing this feature:
/// 1. Every created record ID must begin with `ATTUNE_DEMO_`.
/// 2. Every exact created file must be listed in MomentumDemoManifest.json.
/// 3. Removal deletes manifest-listed files, then performs a type-aware prefix scan
///    of IntentionSets, CheckIns, and ProgressEntries to catch interrupted/orphaned runs.
/// 4. Removal must never delete Intention files, DailyMood, overrides, sessions,
///    audio, extractions, topics, or any record without the reserved demo namespace.
/// 5. The non-Debug launch cleanup in AttuneApp must remain even if the Settings
///    controls/seeder are later removed. It prevents simulator demo files from
///    surviving when a Release build is installed over a Debug build.
/// 6. A full simulator-app uninstall remains the absolute container-level fallback.
@MainActor
enum MomentumDemoDataManager {
    static let idPrefix = "ATTUNE_DEMO_"

    private static let manifestFileName = "MomentumDemoManifest.json"
    private static var manifestURL: URL {
        AppPaths.baseDir.appendingPathComponent(manifestFileName)
    }

    private struct Manifest: Codable {
        let version: Int
        let runID: String
        let createdAt: Date
        let referencedIntentionIDs: [String]
        let createdRelativePaths: [String]
        let protectedFileHashes: [String: String]
        let checkInCount: Int
        let progressEntryCount: Int
    }

    private enum DemoError: LocalizedError {
        case alreadyLoaded
        case noCurrentIntentions
        case overlappingHistoricalSets
        case unsafeManifestPath(String)
        case cleanupIncomplete(Int)

        var errorDescription: String? {
            switch self {
            case .alreadyLoaded:
                return "Momentum demo data already exists. Remove and verify it before loading another run."
            case .noCurrentIntentions:
                return "Add at least one active intention before loading Momentum demo data."
            case .overlappingHistoricalSets:
                return "Existing historical intention sets overlap the demo period. Use a clean simulator or remove the old test history first. No files were changed."
            case .unsafeManifestPath(let path):
                return "Cleanup stopped because the manifest contained an unsafe path: \(path)"
            case .cleanupIncomplete(let count):
                return "Cleanup found \(count) demo record(s) still present."
            }
        }
    }

    static func status() -> MomentumDemoStatus {
        if let manifest = loadManifest() {
            return MomentumDemoStatus(
                hasDemoData: true,
                message: "Loaded: \(manifest.checkInCount) check-ins and \(manifest.progressEntryCount) progress entries."
            )
        }

        let residues = residualDemoRecordURLs()
        if !residues.isEmpty {
            return MomentumDemoStatus(
                hasDemoData: true,
                message: "Found \(residues.count) orphaned demo record(s). Use Remove and Verify."
            )
        }

        return MomentumDemoStatus(hasDemoData: false, message: "No Momentum demo data installed.")
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Adds approximately fourteen days of realistic progress without creating or
    /// modifying intentions. This symbol is absent from physical-device and Release builds.
    static func loadUsingExistingIntentions() throws -> MomentumDemoOperationResult {
        try AppPaths.ensureDirectoriesExist()
        guard !status().hasDemoData else { throw DemoError.alreadyLoaded }

        guard let currentSet = IntentionSetStore.shared.loadCurrentIntentionSet() else {
            throw DemoError.noCurrentIntentions
        }
        let intentions = IntentionStore.shared.loadIntentions(ids: currentSet.intentionIds)
            .filter(\.isActive)
        guard !intentions.isEmpty else { throw DemoError.noCurrentIntentions }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let demoStart = calendar.date(byAdding: .day, value: -13, to: today) ?? today
        let allExistingSets = IntentionSetStore.shared.loadAllIntentionSets()

        // If the current set did not exist for the full demo range, create one ended,
        // demo-only historical set referencing the same intention IDs. Never backdate
        // or rewrite the user's real current set.
        let needsHistoricalSet = currentSet.startedAt > demoStart
        if needsHistoricalSet {
            let overlaps = allExistingSets.contains { set in
                guard set.id != currentSet.id else { return false }
                let setEnd = set.endedAt ?? .distantFuture
                return set.startedAt < currentSet.startedAt && setEnd > demoStart
            }
            guard !overlaps else { throw DemoError.overlappingHistoricalSets }
        }

        let runToken = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).uppercased()
        let runID = "\(idPrefix)\(runToken)"
        var createdURLs: [URL] = []
        var checkInCount = 0
        var progressEntryCount = 0

        let protectedURLs = intentions.map { AppPaths.intentionFileURL(intentionId: $0.id) }
            + [AppPaths.intentionSetFileURL(intentionSetId: currentSet.id)]
        let protectedHashPairs: [(String, String)] = protectedURLs.compactMap { url in
            guard let hash = sha256(url: url) else { return nil }
            return (relativePath(for: url), hash)
        }
        let protectedHashes: [String: String] = Dictionary(uniqueKeysWithValues: protectedHashPairs)

        do {
            if needsHistoricalSet {
                let demoSet = IntentionSet(
                    id: "\(runID)_SET",
                    startedAt: demoStart,
                    endedAt: currentSet.startedAt,
                    intentionIds: intentions.map(\.id)
                )
                try IntentionSetStore.shared.saveIntentionSet(demoSet)
                createdURLs.append(AppPaths.intentionSetFileURL(intentionSetId: demoSet.id))
            }

            // nil means a genuinely missed day: no check-in and no progress record.
            // Values are final daily ratios per intention and intentionally exercise
            // partial, complete, over-target, and mixed-progress chart states.
            let patterns: [[Double]?] = [
                [0.25, 0.10, 0.40, 0.20],
                [0.55, 0.35, 0.65, 0.45],
                nil,
                [1.00, 0.70, 0.90, 0.75],
                [0.35, 0.20, 0.15, 0.30],
                [1.20, 1.00, 0.80, 1.10],
                [0.70, 0.45, 0.55, 0.60],
                nil,
                [0.45, 0.80, 0.35, 0.50],
                [0.90, 0.65, 1.00, 0.85],
                [0.20, 0.30, 0.10, 0.25],
                [1.00, 1.15, 0.75, 0.95],
                [0.60, 0.50, 0.40, 0.55],
                [0.80, 0.70, 0.60, 0.75]
            ]

            for (dayIndex, pattern) in patterns.enumerated() {
                guard let pattern else { continue }
                guard let day = calendar.date(byAdding: .day, value: dayIndex, to: demoStart) else { continue }
                let dayKey = ProgressCalculator.dateKey(for: day)

                let availableSets = IntentionSetStore.shared.loadAllIntentionSets()
                guard let activeSet = StreakCalculator.intentionSetActive(on: dayKey, from: availableSets) else {
                    continue
                }

                // Alternating one/two-check-in days gives the Day chart both a single
                // point state and a realistic cumulative morning-to-evening line.
                let slotRatios: [Double] = dayIndex.isMultiple(of: 3) ? [0.42, 1.0] : [1.0]
                for (slotIndex, slotRatio) in slotRatios.enumerated() {
                    let hour = slotIndex == 0 && slotRatios.count == 2 ? 9 : 18
                    let minute = slotIndex == 0 ? 15 : 20
                    let createdAt = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
                    let checkInID = "\(runID)_CHECKIN_\(dayIndex)_\(slotIndex)"
                    let transcript = demoTranscript(
                        intentions: intentions,
                        finalRatios: pattern,
                        slotRatio: slotRatio
                    )
                    let checkIn = CheckIn(
                        id: checkInID,
                        createdAt: createdAt,
                        intentionSetId: activeSet.id,
                        transcript: transcript,
                        audioFileName: nil
                    )
                    try CheckInStore.shared.saveCheckIn(checkIn)
                    createdURLs.append(AppPaths.checkInFileURL(checkInId: checkInID))
                    checkInCount += 1

                    for (intentionIndex, intention) in intentions.enumerated() {
                        let finalRatio = pattern[intentionIndex % pattern.count]
                        guard finalRatio > 0 else { continue }
                        let target = intention.timeframe.lowercased() == "weekly"
                            ? intention.targetValue / 7.0
                            : intention.targetValue
                        let amount = max(0, target * finalRatio * slotRatio)
                        let entryID = "\(runID)_ENTRY_\(dayIndex)_\(slotIndex)_\(intentionIndex)"
                        let entry = ProgressEntry(
                            id: entryID,
                            createdAt: createdAt,
                            tookPlaceAt: createdAt,
                            dateKey: dayKey,
                            intentionSetId: activeSet.id,
                            intentionId: intention.id,
                            updateType: "TOTAL",
                            amount: amount,
                            unit: intention.unit,
                            confidence: 0.99,
                            evidence: "[Momentum demo] \(intention.title) total",
                            sourceCheckInId: checkInID
                        )
                        try ProgressStore.shared.saveProgressEntry(entry)
                        createdURLs.append(AppPaths.progressEntryFileURL(entryId: entryID))
                        progressEntryCount += 1
                    }
                }
            }

            let manifest = Manifest(
                version: 1,
                runID: runID,
                createdAt: Date(),
                referencedIntentionIDs: intentions.map(\.id),
                createdRelativePaths: createdURLs.map(relativePath(for:)),
                protectedFileHashes: protectedHashes,
                checkInCount: checkInCount,
                progressEntryCount: progressEntryCount
            )
            try saveManifest(manifest)

            return MomentumDemoOperationResult(
                message: "Loaded \(checkInCount) check-ins and \(progressEntryCount) progress entries using \(intentions.count) existing intentions."
            )
        } catch {
            // Transactional rollback for an interrupted/failed load. The reserved
            // run prefix scan catches a file written immediately before an error.
            createdURLs.reversed().forEach { try? FileManager.default.removeItem(at: $0) }
            removeResidualRecords(matchingRunPrefix: runID)
            try? FileManager.default.removeItem(at: manifestURL)
            throw error
        }
    }
    #endif

    /// Removes every demo run safely, even when its manifest is missing or incomplete.
    /// This is intentionally compiled into Release builds for residue protection.
    @discardableResult
    static func removeAndVerify() throws -> MomentumDemoOperationResult {
        let manifest = loadManifest()
        let protectedHashes = manifest?.protectedFileHashes ?? [:]
        var removedPaths = Set<String>()

        if let manifest {
            for relativePath in manifest.createdRelativePaths {
                let url = try safeManifestURL(relativePath: relativePath)
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                    removedPaths.insert(relativePath)
                }
            }
        }

        // Second pass is deliberate: it removes orphaned demo records from a crash,
        // an old run, or a missing manifest, but only when decoded IDs/references use
        // the reserved ATTUNE_DEMO_ namespace.
        for url in residualDemoRecordURLs() {
            try? FileManager.default.removeItem(at: url)
            removedPaths.insert(relativePath(for: url))
        }
        try? FileManager.default.removeItem(at: manifestURL)

        let remaining = residualDemoRecordURLs()
        guard remaining.isEmpty else { throw DemoError.cleanupIncomplete(remaining.count) }

        let changedProtectedFiles = protectedHashes.compactMap { relativePath, originalHash -> String? in
            guard let url = try? safeManifestURL(relativePath: relativePath),
                  let currentHash = sha256(url: url),
                  currentHash == originalHash else {
                return relativePath
            }
            return nil
        }

        let integrityText = changedProtectedFiles.isEmpty
            ? "Protected intention files are unchanged."
            : "Demo records are gone. \(changedProtectedFiles.count) protected file(s) changed while demo mode was active."
        return MomentumDemoOperationResult(
            message: "Removed \(removedPaths.count) demo file(s). Verified 0 demo records remain. \(integrityText)"
        )
    }

    /// Called by non-Debug app launch. Keep this cleanup even if the debug UI is removed.
    static func purgeResidueForNonDebugLaunch() {
        guard status().hasDemoData else { return }
        do {
            let result = try removeAndVerify()
            AppLogger.log(AppLogger.STORE, "Momentum demo residue cleanup: \(result.message)")
        } catch {
            AppLogger.log(AppLogger.ERR, "Momentum demo residue cleanup failed: \(error.localizedDescription)")
        }
    }

    private static func demoTranscript(
        intentions: [Intention],
        finalRatios: [Double],
        slotRatio: Double
    ) -> String {
        intentions.enumerated().map { index, intention in
            let target = intention.timeframe.lowercased() == "weekly"
                ? intention.targetValue / 7.0
                : intention.targetValue
            let amount = target * finalRatios[index % finalRatios.count] * slotRatio
            return "\(intention.title), \(formatted(amount)) \(intention.unit) total today"
        }
        .joined(separator: ". ") + ". [Momentum demo]"
    }

    private static func formatted(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func saveManifest(_ manifest: Manifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    }

    private static func loadManifest() -> Manifest? {
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Manifest.self, from: data)
    }

    private static func sha256(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func relativePath(for url: URL) -> String {
        let base = AppPaths.baseDir.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(base + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(base.count + 1))
    }

    private static func safeManifestURL(relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/"), !relativePath.contains("..") else {
            throw DemoError.unsafeManifestPath(relativePath)
        }
        let url = AppPaths.baseDir.appendingPathComponent(relativePath).standardizedFileURL
        let base = AppPaths.baseDir.standardizedFileURL.path + "/"
        guard url.path.hasPrefix(base) else { throw DemoError.unsafeManifestPath(relativePath) }
        return url
    }

    private static func residualDemoRecordURLs() -> [URL] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let fileManager = FileManager.default
        var matches: [URL] = []

        let setFiles = (try? fileManager.contentsOfDirectory(at: AppPaths.intentionSetsDir, includingPropertiesForKeys: nil)) ?? []
        for url in setFiles where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(IntentionSet.self, from: data) else { continue }
            if record.id.hasPrefix(idPrefix) { matches.append(url) }
        }

        let checkInFiles = (try? fileManager.contentsOfDirectory(at: AppPaths.checkInsDir, includingPropertiesForKeys: nil)) ?? []
        for url in checkInFiles where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(CheckIn.self, from: data) else { continue }
            if record.id.hasPrefix(idPrefix) || record.intentionSetId.hasPrefix(idPrefix) {
                matches.append(url)
            }
        }

        let entryFiles = (try? fileManager.contentsOfDirectory(at: AppPaths.progressEntriesDir, includingPropertiesForKeys: nil)) ?? []
        for url in entryFiles where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(ProgressEntry.self, from: data) else { continue }
            if record.id.hasPrefix(idPrefix)
                || record.intentionSetId.hasPrefix(idPrefix)
                || record.sourceCheckInId.hasPrefix(idPrefix) {
                matches.append(url)
            }
        }

        return Array(Set(matches.map(\.standardizedFileURL))).sorted { $0.path < $1.path }
    }

    private static func removeResidualRecords(matchingRunPrefix runPrefix: String) {
        for url in residualDemoRecordURLs() where url.lastPathComponent.hasPrefix(runPrefix) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
