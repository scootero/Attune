import Foundation

@MainActor
final class IntentionSuggestionStore {
    static let shared = IntentionSuggestionStore()
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? AppPaths.intentionSuggestionsFileURL
    }

    func load() -> IntentionSuggestionSnapshot {
        guard let data = try? Data(contentsOf: fileURL) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(IntentionSuggestionSnapshot.self, from: data)) ?? .empty
    }

    func bootstrapNewInstall(now: Date = Date()) throws {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        var snapshot = IntentionSuggestionSnapshot.empty
        snapshot.firstLaunchAt = now
        try save(snapshot)
    }

    func bootstrapExistingInstallIfNeeded(now: Date = Date()) throws {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        var snapshot = IntentionSuggestionSnapshot.empty
        snapshot.firstLaunchAt = now
        snapshot.isExistingInstall = true
        try save(snapshot)
    }

    func recordNudge(opportunityKey: String, now: Date = Date()) throws {
        var snapshot = load()
        snapshot.lastNudgeAt = now
        try save(snapshot)
    }

    func consume(opportunityKey: String) throws {
        var snapshot = load()
        snapshot.completedOpportunityKeys.insert(opportunityKey)
        try save(snapshot)
    }

    func recordAttempt(opportunityKey: String?, now: Date = Date()) throws {
        var snapshot = load()
        snapshot.lastGenerationAttemptAt = now
        if let opportunityKey { snapshot.completedOpportunityKeys.insert(opportunityKey) }
        try save(snapshot)
    }

    func setOutstanding(_ suggestion: SuggestedIntentionAction) throws {
        var snapshot = load()
        snapshot.outstanding = suggestion
        try save(snapshot)
    }

    func decide(_ outcome: IntentionSuggestionOutcome, suggestion: SuggestedIntentionAction, now: Date = Date()) throws {
        var snapshot = load()
        snapshot.history.append(.init(
            actionId: suggestion.actionId,
            topicKey: suggestion.topicKey,
            outcome: outcome,
            decidedAt: now,
            title: suggestion.title,
            actionFingerprint: suggestion.actionFingerprint,
            actionFamily: suggestion.actionFamily
        ))
        snapshot.outstanding = nil
        try save(snapshot)
    }

    private func save(_ snapshot: IntentionSuggestionSnapshot) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }
}
