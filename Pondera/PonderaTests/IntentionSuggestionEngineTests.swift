import XCTest
@testable import Pondera

final class IntentionSuggestionEngineTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testRapidSuggestionTestingRequiresExplicitLaunchArgument() {
        XCTAssertFalse(RapidIntentionSuggestionTestingFeature.isEnabled(arguments: []))
        XCTAssertTrue(
            RapidIntentionSuggestionTestingFeature.isEnabled(
                arguments: [RapidIntentionSuggestionTestingFeature.launchArgument]
            )
        )
    }

    func testTopicCountsDistinctSessionsAndAssignsMonthBySessionStart() {
        let august = session("august", "2026-08-02T00:00:00Z")
        let july = session("july", "2026-07-31T23:59:59Z")
        let items = [
            item("a", session: august.id, extracted: "2026-08-02T00:01:00Z"),
            item("b", session: august.id, extracted: "2026-08-02T00:02:00Z"),
            item("c", session: july.id, extracted: "2026-08-01T00:01:00Z")
        ]
        let result = IntentionSuggestionEngine.makeTopics(
            topics: [topic(items.map(\.id))], sessions: [august, july], items: items,
            corrections: [:], calendar: calendar, now: date("2026-08-12T00:00:00Z")
        )
        XCTAssertEqual(result.first?.distinctSessionCount, 2)
        XCTAssertEqual(result.first?.currentMonthSessionCount, 1)
        XCTAssertEqual(result.first?.evidence.count, 2)
    }

    func testIncorrectIsOnlyExclusionAndLegacyRejectedRemainsEligible() {
        let one = session("one", "2026-08-01T00:00:00Z")
        let two = session("two", "2026-08-08T00:00:00Z")
        let rejected = item("rejected", session: one.id, reviewState: "rejected")
        let incorrect = item("incorrect", session: two.id)
        let result = IntentionSuggestionEngine.makeTopics(
            topics: [topic([rejected.id, incorrect.id])], sessions: [one, two], items: [rejected, incorrect],
            corrections: [incorrect.id: ItemCorrection(itemId: incorrect.id, isIncorrect: true)]
        )
        XCTAssertEqual(result.first?.distinctSessionCount, 1)
        XCTAssertEqual(result.first?.evidence.first?.itemId, rejected.id)
    }

    func testOrphanOrGroupingCorrectionSkipsTopic() {
        let session = session("one", "2026-08-01T00:00:00Z")
        let item = item("item", session: session.id)
        XCTAssertTrue(IntentionSuggestionEngine.makeTopics(topics: [topic([item.id, "orphan"])], sessions: [session], items: [item], corrections: [:]).isEmpty)
        XCTAssertTrue(IntentionSuggestionEngine.makeTopics(topics: [topic([item.id])], sessions: [session], items: [item], corrections: [item.id: ItemCorrection(itemId: item.id, correctedTitle: "Other")]).isEmpty)
    }

    func testIntroNudgesThenRequestsAfterTwoDistinctSessions() {
        let now = date("2026-08-02T00:00:00Z")
        var snapshot = IntentionSuggestionSnapshot.empty
        snapshot.firstLaunchAt = date("2026-08-01T00:00:00Z")
        XCTAssertEqual(IntentionSuggestionEngine.decide(snapshot: snapshot, topics: [], completedSessionCount: 1, isAtIntentionLimit: false, calendar: calendar, now: now), .nudgeToRecord(opportunityKey: "intro-record-more"))
        let candidate = candidateTopic(count: 2)
        XCTAssertEqual(IntentionSuggestionEngine.decide(snapshot: snapshot, topics: [candidate], completedSessionCount: 2, isAtIntentionLimit: true, calendar: calendar, now: now), .request(topic: candidate, opportunityKey: nil))
    }

    func testThreeDayIntroCooldownThenFourDaySteadyCadence() {
        let start = date("2026-08-01T00:00:00Z")
        let candidate = candidateTopic(count: 4)
        var snapshot = IntentionSuggestionSnapshot.empty
        snapshot.firstLaunchAt = start
        snapshot.history = [.init(actionId: "old", topicKey: "other", outcome: .accepted, decidedAt: date("2026-08-02T00:00:00Z"))]
        XCTAssertEqual(IntentionSuggestionEngine.decide(snapshot: snapshot, topics: [candidate], completedSessionCount: 4, isAtIntentionLimit: false, calendar: calendar, now: date("2026-08-04T23:59:00Z")), .none)
        XCTAssertEqual(IntentionSuggestionEngine.decide(snapshot: snapshot, topics: [candidate], completedSessionCount: 4, isAtIntentionLimit: false, calendar: calendar, now: date("2026-08-05T00:00:00Z")), .request(topic: candidate, opportunityKey: nil))

        snapshot.firstLaunchAt = date("2026-01-01T00:00:00Z")
        snapshot.history[0] = .init(actionId: "old", topicKey: "other", outcome: .accepted, decidedAt: date("2026-01-25T00:00:00Z"))
        XCTAssertEqual(IntentionSuggestionEngine.decide(snapshot: snapshot, topics: [candidate], completedSessionCount: 4, isAtIntentionLimit: false, calendar: calendar, now: date("2026-01-28T23:59:00Z")), .none)
        XCTAssertEqual(IntentionSuggestionEngine.decide(snapshot: snapshot, topics: [candidate], completedSessionCount: 4, isAtIntentionLimit: false, calendar: calendar, now: date("2026-01-29T00:00:00Z")), .request(topic: candidate, opportunityKey: nil))

        let shortSpan = IntentionSuggestionTopic(topicKey: "short", title: "Short", categories: ["personal_growth"], evidence: [], distinctSessionCount: 3, currentMonthSessionCount: 3, firstSessionAt: date("2026-01-26T00:00:00Z"), lastSessionAt: date("2026-01-28T23:59:59Z"))
        XCTAssertEqual(IntentionSuggestionEngine.decide(snapshot: snapshot, topics: [shortSpan], completedSessionCount: 4, isAtIntentionLimit: false, calendar: calendar, now: date("2026-02-10T00:00:00Z")), .none)
    }

    func testDeclinePermanentlySuppressesActionButAllowsNewIdeaForTopic() {
        let now = date("2026-08-12T00:00:00Z")
        let entry = IntentionSuggestionHistoryEntry(actionId: "custom.take_short_walk.5.minutes.daily", topicKey: "fitness|walk", outcome: .declined, decidedAt: now, title: "Take a short walk", actionFingerprint: "take_short_walk", actionFamily: "movement")
        XCTAssertTrue(IntentionSuggestionEngine.isPermanentlyDeclined(actionId: entry.actionId, history: [entry]))
        XCTAssertTrue(IntentionSuggestionEngine.isSuppressed(actionId: "new-id", actionFingerprint: "take_short_walk", title: "Walk briefly", history: [entry], now: now.addingTimeInterval(365 * 86_400)))
        let accepted = IntentionSuggestionHistoryEntry(actionId: "custom.teach_idea.1.times.daily", topicKey: "learning", outcome: .accepted, decidedAt: now, title: "Teach one idea", actionFingerprint: "teach_idea", actionFamily: "learning")
        XCTAssertTrue(IntentionSuggestionEngine.isSuppressed(actionId: "new-id", actionFingerprint: "teach_idea", title: "Teach one idea", history: [accepted], now: now.addingTimeInterval(59 * 86_400)))
        XCTAssertFalse(IntentionSuggestionEngine.isSuppressed(actionId: "new-id", actionFingerprint: "teach_idea", title: "Teach one idea", history: [accepted], now: now.addingTimeInterval(61 * 86_400)))
        var snapshot = IntentionSuggestionSnapshot.empty
        snapshot.isExistingInstall = true
        snapshot.firstLaunchAt = date("2026-01-01T00:00:00Z")
        snapshot.history = [entry]
        let topic = candidateTopic(count: 4, key: entry.topicKey)
        XCTAssertEqual(IntentionSuggestionEngine.decide(snapshot: snapshot, topics: [topic], completedSessionCount: 8, isAtIntentionLimit: false, calendar: calendar, now: now.addingTimeInterval(5 * 86_400)), .request(topic: topic, opportunityKey: nil))
    }

    func testRelatedFragmentedTopicsMergeAcrossDistinctSessions() {
        let sessions = [
            session("one", "2026-08-01T00:00:00Z"),
            session("two", "2026-08-04T00:00:00Z"),
            session("three", "2026-08-08T00:00:00Z")
        ]
        let items = [
            item("a", session: "one", title: "Special Gestures", quote: "I want to surprise my wife with something thoughtful."),
            item("b", session: "two", title: "Relationship Focus", quote: "I want to make more time for my wife."),
            item("c", session: "three", title: "Thoughtful Moments", quote: "I should do small thoughtful things for my wife.")
        ]
        let aggregates = [
            topic(["a"], key: "relationships_social|special_gestures", title: "Special Gestures", categories: ["relationships_social"]),
            topic(["b"], key: "relationships_social|relationship_focus", title: "Relationship Focus", categories: ["relationships_social"]),
            topic(["c"], key: "relationships_social|thoughtful_moments", title: "Thoughtful Moments", categories: ["relationships_social"])
        ]
        let result = IntentionSuggestionEngine.makeTopics(topics: aggregates, sessions: sessions, items: items, corrections: [:], calendar: calendar, now: date("2026-08-12T00:00:00Z"))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.distinctSessionCount, 3)
        XCTAssertEqual(Set(result.first?.evidence.map(\.sessionId) ?? []).count, 3)
    }

    func testRapidModeCountsSpacedSegmentsWithinOneSessionAndBypassesCadence() throws {
        let start = date("2026-08-15T12:00:00Z")
        let segments = [
            segment("segment-1", session: "one", index: 0, startedAt: start),
            segment("segment-2", session: "one", index: 1, startedAt: start.addingTimeInterval(3 * 60)),
            segment("segment-3", session: "one", index: 2, startedAt: start.addingTimeInterval(6 * 60))
        ]
        let oneSession = Session(id: "one", startedAt: start, status: "complete", segments: segments)
        let items = segments.map {
            item("item-\($0.index)", session: oneSession.id, segmentId: $0.id)
        }
        let topics = IntentionSuggestionEngine.makeTopics(
            topics: [topic(items.map(\.id))],
            sessions: [oneSession],
            items: items,
            corrections: [:],
            rapidTestingEnabled: true,
            calendar: calendar,
            now: start.addingTimeInterval(10 * 60)
        )

        let candidate = try XCTUnwrap(topics.first)
        XCTAssertEqual(candidate.distinctSessionCount, 1)
        XCTAssertEqual(candidate.rapidTestMentionCount, 3)
        XCTAssertEqual(candidate.evidence.count, 3)

        var snapshot = IntentionSuggestionSnapshot.empty
        snapshot.firstLaunchAt = start
        snapshot.lastGenerationAttemptAt = start.addingTimeInterval(9 * 60)
        snapshot.history = [.init(
            actionId: "recent",
            topicKey: "other",
            outcome: .accepted,
            decidedAt: start.addingTimeInterval(9 * 60)
        )]
        XCTAssertEqual(
            IntentionSuggestionEngine.decide(
                snapshot: snapshot,
                topics: topics,
                completedSessionCount: 1,
                isAtIntentionLimit: false,
                rapidTestingEnabled: true,
                calendar: calendar,
                now: start.addingTimeInterval(10 * 60)
            ),
            .request(topic: candidate, opportunityKey: nil)
        )
    }

    func testRapidModeDoesNotCountMentionsLessThanThreeMinutesApart() {
        let start = date("2026-08-15T12:00:00Z")
        let segments = [
            segment("segment-1", session: "one", index: 0, startedAt: start),
            segment("segment-2", session: "one", index: 1, startedAt: start.addingTimeInterval(2 * 60)),
            segment("segment-3", session: "one", index: 2, startedAt: start.addingTimeInterval(4 * 60))
        ]
        let oneSession = Session(id: "one", startedAt: start, status: "complete", segments: segments)
        let items = segments.map {
            item("item-\($0.index)", session: oneSession.id, segmentId: $0.id)
        }
        let topics = IntentionSuggestionEngine.makeTopics(
            topics: [topic(items.map(\.id))],
            sessions: [oneSession],
            items: items,
            corrections: [:],
            rapidTestingEnabled: true,
            calendar: calendar,
            now: start.addingTimeInterval(10 * 60)
        )

        XCTAssertEqual(topics.first?.rapidTestMentionCount, 2)
        XCTAssertEqual(
            IntentionSuggestionEngine.decide(
                snapshot: .empty,
                topics: topics,
                completedSessionCount: 1,
                isAtIntentionLimit: false,
                rapidTestingEnabled: true,
                calendar: calendar,
                now: start.addingTimeInterval(10 * 60)
            ),
            .none
        )
    }

    func testActiveIntentionSemanticallyCoversSuggestion() {
        let walk = Intention(title: "Walk", targetValue: 20, unit: "minutes", timeframe: "daily")
        let reading = Intention(title: "Read", targetValue: 10, unit: "pages", timeframe: "daily", aliases: ["reading"])

        XCTAssertTrue(IntentionSuggestionEngine.isCoveredByActiveIntention(
            suggestionTitle: "Take a short walk",
            activeIntentions: [walk]
        ))
        XCTAssertTrue(IntentionSuggestionEngine.isCoveredByActiveIntention(
            suggestionTitle: "Review today’s reading",
            activeIntentions: [reading]
        ))
        XCTAssertFalse(IntentionSuggestionEngine.isCoveredByActiveIntention(
            suggestionTitle: "Send one thoughtful check-in",
            activeIntentions: [walk, reading]
        ))
    }

    @MainActor
    func testStoreDecodesMissingOptionalFieldsAndPersistsDecline() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = directory.appendingPathComponent("suggestions.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(#"{"history":[{"actionId":"legacy","topicKey":"planning","outcome":"declined","decidedAt":"2026-08-01T00:00:00Z"}]}"#.utf8).write(to: file)
        let store = IntentionSuggestionStore(fileURL: file)
        XCTAssertEqual(store.load().history.first?.actionId, "legacy")
        XCTAssertNil(store.load().history.first?.actionFingerprint)

        let evidence = IntentionSuggestionEvidence(itemId: "item", sessionId: "session", sessionDate: date("2026-08-01T00:00:00Z"), quote: "quote")
        var suggestion = SuggestedIntentionAction(actionId: "custom.choose_top_task.1.times.daily", topicKey: "career|planning", topicTitle: "Planning", title: "Choose today’s top task", targetValue: 1, unit: "times", timeframe: "daily", reason: "Planning keeps returning.", evidence: [evidence], sourceTitle: nil, sourceURL: nil, safetyNote: nil, generatedAt: date("2026-08-12T00:00:00Z"))
        suggestion.actionFingerprint = "choose_top_task"
        suggestion.actionFamily = "planning"
        try store.setOutstanding(suggestion)
        try store.decide(.declined, suggestion: suggestion, now: date("2026-08-12T01:00:00Z"))
        XCTAssertNil(store.load().outstanding)
        XCTAssertTrue(IntentionSuggestionEngine.isPermanentlyDeclined(actionId: suggestion.actionId, history: store.load().history))
        XCTAssertEqual(store.load().history.last?.actionFingerprint, "choose_top_task")
    }

    private func candidateTopic(count: Int, key: String = "personal_growth|planning") -> IntentionSuggestionTopic {
        IntentionSuggestionTopic(topicKey: key, title: "Planning", categories: ["personal_growth"], evidence: [], distinctSessionCount: count, currentMonthSessionCount: count, firstSessionAt: date("2026-07-01T00:00:00Z"), lastSessionAt: date("2026-08-01T00:00:00Z"))
    }

    private func session(_ id: String, _ value: String) -> Session { Session(id: id, startedAt: date(value), status: "complete") }
    private func item(_ id: String, session: String, segmentId: String = "s", extracted: String = "2026-08-01T01:00:00Z", reviewState: String = "new", title: String = "Planning", quote: String = "I keep bringing this up", categories: [String] = ["personal_growth"]) -> ExtractedItem {
        ExtractedItem(id: id, sessionId: session, segmentId: segmentId, segmentIndex: 0, type: "state", title: title, summary: "", categories: categories, confidence: 1, strength: 1, sourceQuote: quote, fingerprint: title.lowercased(), reviewState: reviewState, createdAt: extracted, extractedAt: extracted)
    }
    private func segment(_ id: String, session: String, index: Int, startedAt: Date) -> Segment {
        Segment(id: id, sessionId: session, index: index, startedAt: startedAt, audioFileName: "segment_\(index).m4a", status: "done")
    }
    private func topic(_ ids: [String], key: String = "personal_growth|planning", title: String = "Planning", categories: [String] = ["personal_growth"]) -> TopicAggregate {
        var value = TopicAggregate(canonicalKey: "\(title.lowercased())__1", displayTitle: title, firstSeenAtISO: "2026-07-01T00:00:00Z", categories: categories, itemId: ids.first ?? "", topicKey: key)
        value.itemIds = ids
        value.occurrenceCount = ids.count
        return value
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
}
