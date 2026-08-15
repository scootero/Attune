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
        rapidTestingEnabled: Bool = false,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [IntentionSuggestionTopic] {
        let sessionsById = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let itemsById = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let month = calendar.dateInterval(of: .month, for: now)

        let candidates = topics.compactMap { topic -> IntentionSuggestionTopic? in
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
                let evidenceDate: Date
                if rapidTestingEnabled,
                   let segment = session.segments.first(where: { $0.id == item.segmentId }) {
                    evidenceDate = segment.startedAt
                } else {
                    evidenceDate = session.startedAt
                }
                return IntentionSuggestionEvidence(
                    itemId: item.id,
                    sessionId: session.id,
                    sessionDate: evidenceDate,
                    quote: SessionRecapBuilder.truncateQuote(quote, maximumCharacterCount: 180)
                )
            }
            guard !resolvedEvidence.isEmpty else { return nil }

            let selectedEvidence: [IntentionSuggestionEvidence]
            if rapidTestingEnabled {
                selectedEvidence = spacedEvidence(resolvedEvidence)
            } else {
                selectedEvidence = Dictionary(grouping: resolvedEvidence, by: \.sessionId)
                    .compactMap { _, evidence in evidence.max(by: { $0.sessionDate < $1.sessionDate }) }
                    .sorted { $0.sessionDate > $1.sessionDate }
            }
            guard let first = selectedEvidence.last, let last = selectedEvidence.first else { return nil }
            let distinctSessions = Set(selectedEvidence.map(\.sessionId))
            let monthSessions = Set(selectedEvidence.filter { month?.contains($0.sessionDate) == true }.map(\.sessionId))
            var candidate = IntentionSuggestionTopic(
                topicKey: key,
                title: topic.displayTitle,
                categories: topic.categories,
                evidence: Array(selectedEvidence.prefix(5)),
                distinctSessionCount: distinctSessions.count,
                currentMonthSessionCount: monthSessions.count,
                firstSessionAt: first.sessionDate,
                lastSessionAt: last.sessionDate
            )
            if rapidTestingEnabled { candidate.rapidTestMentionCount = selectedEvidence.count }
            return candidate
        }
        return consolidateRelatedTopics(candidates, rapidTestingEnabled: rapidTestingEnabled, calendar: calendar, now: now)
    }

    static func decide(
        snapshot: IntentionSuggestionSnapshot,
        topics: [IntentionSuggestionTopic],
        completedSessionCount: Int,
        isAtIntentionLimit: Bool,
        rapidTestingEnabled: Bool = false,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> IntentionSuggestionDecision {
        // A full intention list can still receive a suggestion because the UI
        // offers an explicit, reviewable swap instead of silently adding one.
        _ = isAtIntentionLimit
        if let outstanding = snapshot.outstanding { return .show(outstanding) }
        if rapidTestingEnabled {
            return bestTopic(topics.filter {
                ($0.rapidTestMentionCount ?? 0) >= RapidIntentionSuggestionTestingFeature.minimumMentionCount
            }).map { .request(topic: $0, opportunityKey: nil) } ?? .none
        }
        if let attempt = snapshot.lastGenerationAttemptAt,
           now.timeIntervalSince(attempt) < 24 * 60 * 60 { return .none }

        // A declined action is permanently suppressed, but its broad topic is
        // still allowed to produce a genuinely different idea later.
        let available = topics
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
        if days <= 20 {
            minimumSessions = 2
            minimumSpan = 0
            cooldown = 3 * 24 * 60 * 60
        } else {
            minimumSessions = 3
            minimumSpan = 3 * 24 * 60 * 60
            cooldown = 4 * 24 * 60 * 60
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

    static func isSuppressed(
        actionId: String,
        actionFingerprint: String?,
        title: String,
        history: [IntentionSuggestionHistoryEntry],
        now: Date = Date()
    ) -> Bool {
        history.contains { entry in
            let exactAction = entry.actionId == actionId
            let exactFingerprint = actionFingerprint.map { $0 == entry.actionFingerprint } ?? false
            let closeDeclinedTitle = entry.outcome == .declined
                && entry.title.map { titlesAreSemanticMatches(title, $0) } == true
            if entry.outcome == .declined {
                return exactAction || exactFingerprint || closeDeclinedTitle
            }
            return (exactAction || exactFingerprint) && now.timeIntervalSince(entry.decidedAt) < 60 * 24 * 60 * 60
        }
    }

    static func isCoveredByActiveIntention(
        suggestionTitle: String,
        activeIntentions: [Intention]
    ) -> Bool {
        let suggestionTerms = coverageTerms(in: suggestionTitle)
        guard !suggestionTerms.isEmpty else { return false }
        return activeIntentions.contains { intention in
            let activeTerms = coverageTerms(in: ([intention.title] + intention.aliases).joined(separator: " "))
            return termsAreSemanticMatches(suggestionTerms, activeTerms)
        }
    }

    private static func titlesAreSemanticMatches(_ lhs: String, _ rhs: String) -> Bool {
        termsAreSemanticMatches(coverageTerms(in: lhs), coverageTerms(in: rhs))
    }

    private static func termsAreSemanticMatches(_ lhs: Set<String>, _ rhs: Set<String>) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        let overlap = lhs.intersection(rhs).count
        if min(lhs.count, rhs.count) == 1 { return overlap == 1 }
        return overlap >= 2 || Double(overlap) / Double(min(lhs.count, rhs.count)) >= 0.6
    }

    private static func coverageTerms(in value: String) -> Set<String> {
        let ignored: Set<String> = [
            "a", "an", "and", "at", "daily", "do", "for", "from", "in", "minute", "minutes",
            "better", "daily", "feel", "keep", "more", "my", "need", "of", "one", "really", "say",
            "short", "take", "talk", "the", "thing", "things", "think", "this", "times", "to", "today",
            "two", "want", "weekly"
        ]
        let words = value.lowercased().split { !$0.isLetter && !$0.isNumber }
        return Set(words.compactMap { word -> String? in
            var term = String(word)
            if term.count > 5, term.hasSuffix("ing") { term.removeLast(3) }
            else if term.count > 4, term.hasSuffix("ed") { term.removeLast(2) }
            else if term.count > 4, term.hasSuffix("s") { term.removeLast() }
            if term == "record" { term = "log" }
            if term == "nightly" { term = "night" }
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

    private static func consolidateRelatedTopics(
        _ topics: [IntentionSuggestionTopic],
        rapidTestingEnabled: Bool,
        calendar: Calendar,
        now: Date
    ) -> [IntentionSuggestionTopic] {
        var groups: [[IntentionSuggestionTopic]] = []
        for topic in topics.sorted(by: { $0.topicKey < $1.topicKey }) {
            let terms = identityTerms(for: topic)
            if let index = groups.firstIndex(where: { group in
                guard let representative = group.first else { return false }
                return !Set(representative.categories).isDisjoint(with: topic.categories)
                    && group.contains { !identityTerms(for: $0).isDisjoint(with: terms) }
            }) {
                groups[index].append(topic)
            } else {
                groups.append([topic])
            }
        }
        let month = calendar.dateInterval(of: .month, for: now)
        return groups.compactMap { group in
            guard let representative = bestTopic(group) else { return nil }
            let selectedEvidence: [IntentionSuggestionEvidence]
            if rapidTestingEnabled {
                selectedEvidence = spacedEvidence(group.flatMap(\.evidence))
            } else {
                selectedEvidence = Dictionary(grouping: group.flatMap(\.evidence), by: \.sessionId)
                    .compactMap { _, values in values.max(by: { $0.sessionDate < $1.sessionDate }) }
                    .sorted { $0.sessionDate > $1.sessionDate }
            }
            guard let newest = selectedEvidence.first, let oldest = selectedEvidence.last else { return nil }
            let distinctSessions = Set(selectedEvidence.map(\.sessionId))
            var topic = IntentionSuggestionTopic(
                topicKey: group.map(\.topicKey).sorted().joined(separator: "+"),
                title: representative.title,
                categories: Array(Set(group.flatMap(\.categories))).sorted(),
                evidence: Array(selectedEvidence.prefix(5)),
                distinctSessionCount: distinctSessions.count,
                currentMonthSessionCount: Set(selectedEvidence.filter { month?.contains($0.sessionDate) == true }.map(\.sessionId)).count,
                firstSessionAt: oldest.sessionDate,
                lastSessionAt: newest.sessionDate
            )
            if rapidTestingEnabled { topic.rapidTestMentionCount = selectedEvidence.count }
            return topic
        }
    }

    private static func spacedEvidence(_ evidence: [IntentionSuggestionEvidence]) -> [IntentionSuggestionEvidence] {
        let chronological = evidence.sorted {
            if $0.sessionDate != $1.sessionDate { return $0.sessionDate < $1.sessionDate }
            return $0.itemId < $1.itemId
        }
        var accepted: [IntentionSuggestionEvidence] = []
        for value in chronological {
            guard let previous = accepted.last else {
                accepted.append(value)
                continue
            }
            if value.sessionDate.timeIntervalSince(previous.sessionDate) >= RapidIntentionSuggestionTestingFeature.minimumMentionSpacing {
                accepted.append(value)
            }
        }
        return accepted.sorted { $0.sessionDate > $1.sessionDate }
    }

    private static func identityTerms(for topic: IntentionSuggestionTopic) -> Set<String> {
        let evidence = topic.evidence.map(\.quote).joined(separator: " ")
        return coverageTerms(in: "\(topic.title) \(evidence)")
    }
}
