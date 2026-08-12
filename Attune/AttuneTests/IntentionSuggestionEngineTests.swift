import XCTest
@testable import Attune

final class IntentionSuggestionEngineTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
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

    func testNewUserDayThreeNudgesThenRequestsAfterEnoughSessions() {
        let now = date("2026-08-04T00:00:00Z")
        var snapshot = IntentionSuggestionSnapshot.empty
        snapshot.firstLaunchAt = date("2026-08-01T00:00:00Z")
        XCTAssertEqual(IntentionSuggestionEngine.decide(snapshot: snapshot, topics: [], completedSessionCount: 2, isAtIntentionLimit: false, calendar: calendar, now: now), .nudgeToRecord(opportunityKey: "day3"))
        let candidate = candidateTopic(count: 2)
        XCTAssertEqual(IntentionSuggestionEngine.decide(snapshot: snapshot, topics: [candidate], completedSessionCount: 3, isAtIntentionLimit: false, calendar: calendar, now: now), .request(topic: candidate, opportunityKey: "day3"))
    }

    func testDeclinePermanentlySuppressesActionAndPausesTopicNinetyDays() {
        let now = date("2026-08-12T00:00:00Z")
        let entry = IntentionSuggestionHistoryEntry(actionId: "movement.walk_5_daily", topicKey: "fitness|walk", outcome: .declined, decidedAt: now)
        XCTAssertTrue(IntentionSuggestionEngine.isPermanentlyDeclined(actionId: entry.actionId, history: [entry]))
        var snapshot = IntentionSuggestionSnapshot.empty
        snapshot.isExistingInstall = true
        snapshot.history = [entry]
        XCTAssertEqual(IntentionSuggestionEngine.decide(snapshot: snapshot, topics: [candidateTopic(count: 4, key: entry.topicKey)], completedSessionCount: 8, isAtIntentionLimit: false, calendar: calendar, now: now.addingTimeInterval(30 * 86_400)), .none)
    }

    @MainActor
    func testStoreDecodesMissingOptionalFieldsAndPersistsDecline() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = directory.appendingPathComponent("suggestions.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{}".utf8).write(to: file)
        let store = IntentionSuggestionStore(fileURL: file)
        XCTAssertEqual(store.load(), .empty)

        let evidence = IntentionSuggestionEvidence(itemId: "item", sessionId: "session", sessionDate: date("2026-08-01T00:00:00Z"), quote: "quote")
        let suggestion = SuggestedIntentionAction(actionId: "routine.top_task_daily", topicKey: "career|planning", topicTitle: "Planning", title: "Choose today’s top task", targetValue: 1, unit: "times", timeframe: "daily", reason: "Planning keeps returning.", evidence: [evidence], sourceTitle: nil, sourceURL: nil, safetyNote: nil, generatedAt: date("2026-08-12T00:00:00Z"))
        try store.setOutstanding(suggestion)
        try store.decide(.declined, suggestion: suggestion, now: date("2026-08-12T01:00:00Z"))
        XCTAssertNil(store.load().outstanding)
        XCTAssertTrue(IntentionSuggestionEngine.isPermanentlyDeclined(actionId: suggestion.actionId, history: store.load().history))
    }

    private func candidateTopic(count: Int, key: String = "personal_growth|planning") -> IntentionSuggestionTopic {
        IntentionSuggestionTopic(topicKey: key, title: "Planning", categories: ["personal_growth"], evidence: [], distinctSessionCount: count, currentMonthSessionCount: count, firstSessionAt: date("2026-07-01T00:00:00Z"), lastSessionAt: date("2026-08-01T00:00:00Z"))
    }

    private func session(_ id: String, _ value: String) -> Session { Session(id: id, startedAt: date(value), status: "complete") }
    private func item(_ id: String, session: String, extracted: String = "2026-08-01T01:00:00Z", reviewState: String = "new") -> ExtractedItem {
        ExtractedItem(id: id, sessionId: session, segmentId: "s", segmentIndex: 0, type: "state", title: "Planning", summary: "", categories: ["personal_growth"], confidence: 1, strength: 1, sourceQuote: "I keep bringing this up", fingerprint: "planning", reviewState: reviewState, createdAt: extracted, extractedAt: extracted)
    }
    private func topic(_ ids: [String]) -> TopicAggregate {
        var value = TopicAggregate(canonicalKey: "planning__1", displayTitle: "Planning", firstSeenAtISO: "2026-07-01T00:00:00Z", categories: ["personal_growth"], itemId: ids.first ?? "", topicKey: "personal_growth|planning")
        value.itemIds = ids
        value.occurrenceCount = ids.count
        return value
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
}
