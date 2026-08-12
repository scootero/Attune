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
        // A full intention list can still receive a suggestion because the UI
        // offers an explicit, reviewable swap instead of silently adding one.
        _ = isAtIntentionLimit
        if let outstanding = snapshot.outstanding { return .show(outstanding) }
        if let attempt = snapshot.lastGenerationAttemptAt,
           now.timeIntervalSince(attempt) < 24 * 60 * 60 { return .none }

        let declined = snapshot.history.filter { $0.outcome == .declined }
        let available = topics.filter { topic in
            // "Not for me" is durable for both the exact action and the theme
            // that produced it. Do not quietly bring the same kind of suggestion
            // back after an arbitrary cooling-off period.
            !declined.contains { $0.topicKey == topic.topicKey }
        }
        // The feature gets its own introduction clock for every user. It starts
        // responsive, then deliberately quiets down as Attune learns more.
        let programStart = snapshot.firstLaunchAt ?? now
        let days = max(0, calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: programStart),
            to: calendar.startOfDay(for: now)
        ).day ?? 0)
        let minimumSessions: Int
        let minimumSpan: TimeInterval
        let cooldown: TimeInterval
        switch days {
        case 0...20:
            minimumSessions = 2
            minimumSpan = 0
            cooldown = 4 * 24 * 60 * 60
        case 21...50:
            minimumSessions = 3
            minimumSpan = 0
            cooldown = 7 * 24 * 60 * 60
        default:
            minimumSessions = 4
            minimumSpan = 14 * 24 * 60 * 60
            cooldown = 14 * 24 * 60 * 60
        }

        guard completedSessionCount >= minimumSessions else {
            if days <= 20,
               snapshot.lastNudgeAt.map({ now.timeIntervalSince($0) >= cooldown }) ?? true {
                return .nudgeToRecord(opportunityKey: "intro-record-more")
            }
            return .none
        }
        if let latest = snapshot.history.map(\.decidedAt).max(), now.timeIntervalSince(latest) < cooldown { return .none }
        return bestTopic(available.filter {
            $0.distinctSessionCount >= minimumSessions && $0.lastSessionAt.timeIntervalSince($0.firstSessionAt) >= minimumSpan
        }).map { .request(topic: $0, opportunityKey: nil) } ?? .none
    }

    static func isPermanentlyDeclined(actionId: String, history: [IntentionSuggestionHistoryEntry]) -> Bool {
        history.contains { $0.actionId == actionId && $0.outcome == .declined }
    }

    static func isCoveredByActiveIntention(
        suggestionTitle: String,
        activeIntentions: [Intention]
    ) -> Bool {
        let suggestionTerms = coverageTerms(in: suggestionTitle)
        guard !suggestionTerms.isEmpty else { return false }
        return activeIntentions.contains { intention in
            let activeTerms = coverageTerms(in: ([intention.title] + intention.aliases).joined(separator: " "))
            return !suggestionTerms.isDisjoint(with: activeTerms)
        }
    }

    private static func coverageTerms(in value: String) -> Set<String> {
        let ignored: Set<String> = [
            "a", "an", "and", "at", "daily", "do", "for", "from", "in", "minute", "minutes",
            "my", "of", "one", "short", "take", "the", "this", "times", "to", "today", "two", "weekly"
        ]
        let words = value.lowercased().split { !$0.isLetter && !$0.isNumber }
        return Set(words.compactMap { word -> String? in
            var term = String(word)
            if term.count > 5, term.hasSuffix("ing") { term.removeLast(3) }
            else if term.count > 4, term.hasSuffix("ed") { term.removeLast(2) }
            else if term.count > 4, term.hasSuffix("s") { term.removeLast() }
            return term.count >= 3 && !ignored.contains(term) ? term : nil
        })
    }

    private static func bestTopic(_ topics: [IntentionSuggestionTopic]) -> IntentionSuggestionTopic? {
        topics.sorted {
            if $0.distinctSessionCount != $1.distinctSessionCount { return $0.distinctSessionCount > $1.distinctSessionCount }
            if $0.lastSessionAt != $1.lastSessionAt { return $0.lastSessionAt > $1.lastSessionAt }
            return $0.topicKey < $1.topicKey
        }.first
    }
}
