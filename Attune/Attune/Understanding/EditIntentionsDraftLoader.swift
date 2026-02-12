//
//  EditIntentionsDraftLoader.swift
//  Attune
//
//  Loads current intention set + intentions for Edit Intentions sheet on a background queue.
//  Prevents main-thread blocking when the sheet opens. Uses same file I/O logic as stores
//  but runs off main thread (no @MainActor).
//

import Foundation

/// Draft intention shape for Edit Intentions form (mirrors EditIntentionsView.DraftIntention).
/// Defined here so the loader can return it without depending on the view.
struct DraftIntentionLoadResult {
    var id: String
    var title: String
    var targetValue: Double
    var unit: String
    var timeframe: String
}

/// Loads draft intentions for the Edit Intentions sheet on a background queue.
/// Call from UI; completion is always invoked on the main queue for safe @State updates.
enum EditIntentionsDraftLoader {

    /// Loads current intention set and its intentions from disk on background.
    /// - Parameter completion: Called on main queue with draft rows (empty if no current set).
    static func loadDraftInBackground(completion: @escaping ([DraftIntentionLoadResult]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let drafts = loadDraftOffMainThread()
            DispatchQueue.main.async {
                completion(drafts)
            }
        }
    }

    // MARK: - Private: File I/O (mirrors store logic, runs on background queue)

    private static func loadDraftOffMainThread() -> [DraftIntentionLoadResult] {
        // Load current intention set (read-only; no create — if none exists we show empty)
        guard let intentionSet = loadCurrentIntentionSetOffMain() else {
            return []
        }

        // Load intentions for this set
        let intentions = loadIntentionsOffMain(ids: intentionSet.intentionIds)
            .filter { $0.isActive }

        guard !intentions.isEmpty else {
            return []
        }

        // Map to draft format for the form
        return intentions.map { i in
            DraftIntentionLoadResult(
                id: i.id,
                title: i.title,
                targetValue: i.targetValue,
                unit: i.unit,
                timeframe: i.timeframe
            )
        }
    }

    /// Loads the current active intention set (endedAt == nil). Does NOT create one.
    private static func loadCurrentIntentionSetOffMain() -> IntentionSet? {
        let all = loadAllIntentionSetsOffMain()
        let current = all.filter { $0.endedAt == nil }
        return current.sorted { $0.startedAt > $1.startedAt }.first
    }

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

    private static func loadIntentionsOffMain(ids: [String]) -> [Intention] {
        ids.compactMap { id -> Intention? in
            let fileURL = AppPaths.intentionFileURL(intentionId: id)
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(Intention.self, from: data)
        }
    }
}
