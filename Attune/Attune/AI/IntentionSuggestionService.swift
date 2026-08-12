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
        let evidenceItemIds: [String]
        let sourceTitle: String?
        let sourceURL: String?
        let safetyNote: String?
    }

    static func generate(
        topic: IntentionSuggestionTopic,
        activeIntentions: [Intention],
        declinedActionIds: [String],
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
                ["title": $0.title, "aliases": $0.aliases]
            },
            "declinedActionIds": Array(declinedActionIds.prefix(100))
        ]
        let json = try await OpenAIClient.serverOwnedTask(.intentionSuggestion, body: body)
        let decoder = JSONDecoder()
        guard let data = json.data(using: .utf8), let response = try? decoder.decode(Response.self, from: data) else {
            throw IntentionSuggestionServiceError.invalidResponse
        }
        guard let payload = response.suggestion else { return nil }
        guard payload.targetValue > 0,
              ["daily", "weekly"].contains(payload.timeframe),
              !payload.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !declinedActionIds.contains(payload.actionId) else {
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
        suggestion.distinctSessionCount = topic.distinctSessionCount
        suggestion.currentMonthSessionCount = topic.currentMonthSessionCount
        return suggestion
    }
}
