import Foundation

enum InsightAIService {
    struct AIInsight: Decodable {
        let title: String
        let detail: String
        let confidence: String
        let dates: [String]
    }

    static func analyze(
        intentions: [Intention],
        progressEntries: [ProgressEntry],
        moods: [DailyMood]
    ) async throws -> [AIInsight] {
        let intentionByID = Dictionary(uniqueKeysWithValues: intentions.map { ($0.id, $0) })
        let intentionDays = progressEntries.compactMap { entry -> [String: Any]? in
            guard let intention = intentionByID[entry.intentionId], let mood = moods.first(where: { $0.dateKey == entry.dateKey })?.moodScore else { return nil }
            return [
                "date": entry.dateKey,
                "intention": intention.title,
                "moodScore": mood,
                "progress": entry.amount,
                "target": intention.targetValue,
                "unit": intention.unit
            ]
        }
        let moodHistory = moods.compactMap { mood -> [String: Any]? in
            guard let score = mood.moodScore else { return nil }
            return ["date": mood.dateKey, "moodScore": score]
        }
        guard !intentionDays.isEmpty else { return [] }

        let json = try await OpenAIClient.serverOwnedTask(
            .insights,
            body: ["intentionDays": intentionDays, "moodHistory": moodHistory]
        )
        let decoded = try JSONDecoder().decode([String: [AIInsight]].self, from: Data(json.utf8))
        return decoded["insights"] ?? []
    }
}
