import Foundation

enum IntentionSuggestionServiceError: Error {
    case invalidResponse
}

enum IntentionSuggestionService {
    private struct Response: Decodable {
        let suggestion: Payload?
    }

    private struct Payload: Decodable {
        let actionId: String
        let title: String
        let targetValue: Double
        let unit: String
        let timeframe: String
        let reason: String
        let actionFingerprint: String
        let actionFamily: String
        let evidenceItemIds: [String]
        let sourceTitle: String?
        let sourceURL: String?
        let safetyNote: String?
    }

    static func generate(
        topic: IntentionSuggestionTopic,
        activeIntentions: [Intention],
        history: [IntentionSuggestionHistoryEntry],
        recentProgressDaysByIntentionId: [String: Int],
        rapidTestMode: Bool = false,
        now: Date = Date()
    ) async throws -> SuggestedIntentionAction? {
        let formatter = ISO8601DateFormatter()
        let body: [String: Any] = [
            "topic": [
                "key": topic.topicKey,
                "title": topic.title,
                "categories": topic.categories
            ],
            "evidence": topic.evidence.map {
                ["itemId": $0.itemId, "sessionDate": formatter.string(from: $0.sessionDate), "quote": $0.quote]
            },
            "activeIntentions": activeIntentions.map {
                [
                    "id": $0.id,
                    "title": $0.title,
                    "aliases": $0.aliases,
                    "targetValue": $0.targetValue,
                    "unit": $0.unit,
                    "timeframe": $0.timeframe,
                    "recentProgressDays": recentProgressDaysByIntentionId[$0.id] ?? 0
                ] as [String: Any]
            },
            "declinedActionIds": Array(history.filter { $0.outcome == .declined }.map(\.actionId).prefix(100)),
            "rapidTestMode": rapidTestMode,
            "suggestionHistory": Array(history.suffix(100)).map {
                var value: [String: Any] = [
                    "actionId": $0.actionId,
                    "outcome": $0.outcome.rawValue,
                    "decidedAt": formatter.string(from: $0.decidedAt)
                ]
                if let title = $0.title { value["title"] = title }
                if let fingerprint = $0.actionFingerprint { value["actionFingerprint"] = fingerprint }
                if let family = $0.actionFamily { value["actionFamily"] = family }
                return value
            }
        ]
        let json = try await OpenAIClient.serverOwnedTask(.intentionSuggestion, body: body)
        let decoder = JSONDecoder()
        guard let data = json.data(using: .utf8), let response = try? decoder.decode(Response.self, from: data) else {
            throw IntentionSuggestionServiceError.invalidResponse
        }
        guard let payload = response.suggestion else { return nil }
        guard payload.targetValue > 0,
              ["daily", "weekly"].contains(payload.timeframe),
              ["pages", "minutes", "sessions", "steps", "reps", "cups", "glasses", "times"].contains(payload.unit),
              !payload.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !IntentionSuggestionEngine.isSuppressed(
                  actionId: payload.actionId,
                  actionFingerprint: payload.actionFingerprint,
                  title: payload.title,
                  history: history,
                  now: now
              ) else {
            throw IntentionSuggestionServiceError.invalidResponse
        }
        let evidenceById = Dictionary(uniqueKeysWithValues: topic.evidence.map { ($0.itemId, $0) })
        let evidence = payload.evidenceItemIds.compactMap { evidenceById[$0] }
        guard evidence.count == payload.evidenceItemIds.count, !evidence.isEmpty else {
            throw IntentionSuggestionServiceError.invalidResponse
        }
        var suggestion = SuggestedIntentionAction(
            actionId: payload.actionId,
            topicKey: topic.topicKey,
            topicTitle: topic.title,
            title: payload.title,
            targetValue: payload.targetValue,
            unit: payload.unit,
            timeframe: payload.timeframe,
            reason: payload.reason,
            evidence: evidence,
            sourceTitle: payload.sourceTitle,
            sourceURL: payload.sourceURL,
            safetyNote: payload.safetyNote,
            generatedAt: now
        )
        suggestion.actionFingerprint = payload.actionFingerprint
        suggestion.actionFamily = payload.actionFamily
        suggestion.distinctSessionCount = topic.distinctSessionCount
        suggestion.currentMonthSessionCount = topic.currentMonthSessionCount
        suggestion.rapidTestMentionCount = topic.rapidTestMentionCount
        return suggestion
    }
}
