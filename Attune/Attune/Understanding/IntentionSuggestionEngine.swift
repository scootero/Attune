import Foundation

enum IntentionSuggestionDecision: Equatable {
    case show(SuggestedIntentionAction)
    case nudgeToRecord(opportunityKey: String)
    case request(topic: IntentionSuggestionTopic, opportunityKey: String?)
    case consume(opportunityKey: String)
    case none
}

enum IntentionSuggestionEngine {
    static func makeTopics(
        topics: [TopicAggregate],
        sessions: [Session],
        items: [ExtractedItem],
        corrections: [String: ItemCorrection],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [IntentionSuggestionTopic] {
        let sessionsById = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let itemsById = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let month = calendar.dateInterval(of: .month, for: now)

        return topics.compactMap { topic in
            let key = topic.topicKey ?? topic.canonicalKey
            guard !key.isEmpty, !topic.itemIds.isEmpty else { return nil }
            guard !topic.itemIds.contains(where: {
                guard let correction = corrections[$0] else { return false }
                return correction.correctedTitle != nil || correction.correctedCategories != nil
            }) else { return nil }

            let resolved = topic.itemIds.compactMap { itemsById[$0] }
            guard resolved.count == topic.itemIds.count else { return nil }
            let eligible = resolved.filter { corrections[$0.id]?.isIncorrect != true }
            let resolvedEvidence = eligible.compactMap { item -> IntentionSuggestionEvidence? in
                guard let session = sessionsById[item.sessionId], session.status == "complete" else { return nil }
                let quote = SessionRecapBuilder.normalizeWhitespace(item.sourceQuote)
                guard !quote.isEmpty else { return nil }
                return IntentionSuggestionEvidence(
                    itemId: item.id,
                    sessionId: session.id,
                    sessionDate: session.startedAt,
                    quote: SessionRecapBuilder.truncateQuote(quote, maximumCharacterCount: 180)
                )
            }
            guard !resolvedEvidence.isEmpty else { return nil }

            let newestPerSession = Dictionary(grouping: resolvedEvidence, by: \.sessionId)
                .compactMap { _, evidence in evidence.max(by: { $0.sessionDate < $1.sessionDate }) }
                .sorted { $0.sessionDate > $1.sessionDate }
            guard let first = newestPerSession.last, let last = newestPerSession.first else { return nil }
            let monthCount = newestPerSession.filter { month?.contains($0.sessionDate) == true }.count
            return IntentionSuggestionTopic(
                topicKey: key,
                title: topic.displayTitle,
                categories: topic.categories,
                evidence: Array(newestPerSession.prefix(5)),
                distinctSessionCount: newestPerSession.count,
                currentMonthSessionCount: monthCount,
                firstSessionAt: first.sessionDate,
                lastSessionAt: last.sessionDate
            )
        }
    }

    static func decide(
        snapshot: IntentionSuggestionSnapshot,
        topics: [IntentionSuggestionTopic],
        completedSessionCount: Int,
        isAtIntentionLimit: Bool,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> IntentionSuggestionDecision {
        guard !isAtIntentionLimit else { return .none }
        if let outstanding = snapshot.outstanding { return .show(outstanding) }
        if let attempt = snapshot.lastGenerationAttemptAt,
           now.timeIntervalSince(attempt) < 24 * 60 * 60 { return .none }

        let declined = snapshot.history.filter { $0.outcome == .declined }
        let available = topics.filter { topic in
            !declined.contains { $0.topicKey == topic.topicKey && now.timeIntervalSince($0.decidedAt) < 90 * 24 * 60 * 60 }
        }
        if let latestDecision = snapshot.history.map(\.decidedAt).max(),
           now.timeIntervalSince(latestDecision) < 7 * 24 * 60 * 60 {
            return .none
        }

        let days = snapshot.firstLaunchAt.map { max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: calendar.startOfDay(for: now)).day ?? 0) }
        var opportunity: (key: String, minimumSessions: Int)?
        if !snapshot.isExistingInstall, let days {
            if (3...9).contains(days), !snapshot.completedOpportunityKeys.contains("day3") {
                opportunity = ("day3", 2)
            } else if days >= 10, !snapshot.completedOpportunityKeys.contains("day10") {
                opportunity = ("day10", 2)
            }
        }

        if let opportunity {
            guard completedSessionCount >= 3 else {
                if let last = snapshot.lastNudgeAt, now.timeIntervalSince(last) < 7 * 24 * 60 * 60 { return .none }
                return .nudgeToRecord(opportunityKey: opportunity.key)
            }
            guard let topic = bestTopic(available.filter { $0.distinctSessionCount >= opportunity.minimumSessions }) else {
                return .consume(opportunityKey: opportunity.key)
            }
            return .request(topic: topic, opportunityKey: opportunity.key)
        }

        let isRamp = !snapshot.isExistingInstall && (days ?? 25) < 25
        let minimumSessions = isRamp ? 3 : 4
        let minimumSpan: TimeInterval = isRamp ? 0 : 14 * 24 * 60 * 60
        let cooldown: TimeInterval = isRamp ? 7 * 24 * 60 * 60 : 14 * 24 * 60 * 60
        if let latest = snapshot.history.map(\.decidedAt).max(), now.timeIntervalSince(latest) < cooldown { return .none }
        return bestTopic(available.filter {
            $0.distinctSessionCount >= minimumSessions && $0.lastSessionAt.timeIntervalSince($0.firstSessionAt) >= minimumSpan
        }).map { .request(topic: $0, opportunityKey: nil) } ?? .none
    }

    static func isPermanentlyDeclined(actionId: String, history: [IntentionSuggestionHistoryEntry]) -> Bool {
        history.contains { $0.actionId == actionId && $0.outcome == .declined }
    }

    private static func bestTopic(_ topics: [IntentionSuggestionTopic]) -> IntentionSuggestionTopic? {
        topics.sorted {
            if $0.distinctSessionCount != $1.distinctSessionCount { return $0.distinctSessionCount > $1.distinctSessionCount }
            if $0.lastSessionAt != $1.lastSessionAt { return $0.lastSessionAt > $1.lastSessionAt }
            return $0.topicKey < $1.topicKey
        }.first
    }
}
