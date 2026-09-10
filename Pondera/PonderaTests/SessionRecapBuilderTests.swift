import XCTest
@testable import Pondera

final class SessionRecapBuilderTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testRecurringTopicCountsDistinctSessionsAndUsesSessionStartedAt() {
        let current = session("current", "2026-08-31T23:30:00Z")
        let earlier = session("earlier", "2026-08-01T00:00:00Z")
        let previousMonth = session("july", "2026-07-31T23:59:59Z")
        let currentItem = item("current-item", sessionId: current.id)
        let duplicateSameSession = item("same-session-item", sessionId: current.id)
        let earlierItem = item("earlier-item", sessionId: earlier.id)
        let priorMonthItem = item("prior-month-item", sessionId: previousMonth.id)
        let topic = topic(
            title: "Career Change",
            itemIds: [currentItem.id, duplicateSameSession.id, earlierItem.id, priorMonthItem.id]
        )

        let recap = makeRecap(
            current: current,
            currentItems: [currentItem, duplicateSameSession],
            sessions: [current, earlier, previousMonth],
            allItems: [currentItem, duplicateSameSession, earlierItem, priorMonthItem],
            topics: [topic],
            now: date("2026-08-31T23:59:00Z")
        )

        XCTAssertEqual(recap.headline, "You mentioned Career Change across 2 sessions this month.")
    }

    func testSessionStartingAcrossMonthBoundaryIsNotAssignedByItemTimestamp() {
        let current = session("current", "2026-08-02T12:00:00Z")
        let julySession = session("july", "2026-07-31T23:59:59Z")
        let currentItem = item("current-item", sessionId: current.id)
        let julyItem = item(
            "july-item",
            sessionId: julySession.id,
            extractedAt: "2026-08-01T00:01:00Z"
        )

        let recap = makeRecap(
            current: current,
            currentItems: [currentItem],
            sessions: [current, julySession],
            allItems: [currentItem, julyItem],
            topics: [topic(title: "Running", itemIds: [currentItem.id, julyItem.id])],
            now: date("2026-08-10T00:00:00Z")
        )

        XCTAssertEqual(recap.headline, "1 thing worth remembering.")
    }

    func testOrphanedTopicSkipsToCorrectedCommitmentFallback() {
        let current = session("current", "2026-08-10T12:00:00Z")
        let earlier = session("earlier", "2026-08-01T12:00:00Z")
        let currentItem = item("current-item", sessionId: current.id, type: .intention)
        let earlierItem = item("earlier-item", sessionId: earlier.id)
        let corrections = [
            currentItem.id: ItemCorrection(itemId: currentItem.id, correctedType: ExtractedItem.ItemType.commitment)
        ]

        let recap = makeRecap(
            current: current,
            currentItems: [currentItem],
            sessions: [current, earlier],
            allItems: [currentItem, earlierItem],
            topics: [topic(title: "Planning", itemIds: [currentItem.id, earlierItem.id, "orphan"])],
            corrections: corrections
        )

        XCTAssertEqual(recap.headline, "One thing you said you’d do.")
    }

    func testTitleOrCategoryCorrectionMakesTopicUnreliableAndFallsBack() {
        for correction in [
            ItemCorrection(itemId: "earlier-item", correctedTitle: "Different subject"),
            ItemCorrection(itemId: "earlier-item", correctedCategories: [ExtractedItem.Category.moneyFinance])
        ] {
            let current = session("current", "2026-08-10T12:00:00Z")
            let earlier = session("earlier", "2026-08-01T12:00:00Z")
            let currentItem = item("current-item", sessionId: current.id)
            let earlierItem = item("earlier-item", sessionId: earlier.id)

            let recap = makeRecap(
                current: current,
                currentItems: [currentItem],
                sessions: [current, earlier],
                allItems: [currentItem, earlierItem],
                topics: [topic(title: "Planning", itemIds: [currentItem.id, earlierItem.id])],
                corrections: [correction.itemId: correction]
            )

            XCTAssertEqual(recap.headline, "1 thing worth remembering.")
        }
    }

    func testIncorrectIsOnlyExclusionRuleAndLegacyRejectedRemainsEligible() {
        let current = session("current", "2026-08-10T12:00:00Z")
        let rejected = item(
            "rejected",
            sessionId: current.id,
            type: .commitment,
            reviewState: ExtractedItem.ReviewState.rejected,
            sourceQuote: "I will still do this"
        )

        let eligible = makeRecap(current: current, currentItems: [rejected])
        XCTAssertEqual(eligible.headline, "One thing you said you’d do.")
        XCTAssertEqual(eligible.quote, "I will still do this")

        let excluded = makeRecap(
            current: current,
            currentItems: [rejected],
            corrections: [rejected.id: ItemCorrection(itemId: rejected.id, isIncorrect: true)]
        )
        XCTAssertEqual(excluded.headline, "Nothing new was captured.")
        XCTAssertNil(excluded.quote)
    }

    func testCorrectedTypesDriveCommitmentCountAndPluralization() {
        let current = session("current", "2026-08-10T12:00:00Z")
        let first = item("first", sessionId: current.id, type: .intention)
        let second = item("second", sessionId: current.id, type: .state)
        let corrections = [
            first.id: ItemCorrection(itemId: first.id, correctedType: ExtractedItem.ItemType.commitment),
            second.id: ItemCorrection(itemId: second.id, correctedType: ExtractedItem.ItemType.commitment)
        ]

        let recap = makeRecap(
            current: current,
            currentItems: [first, second],
            corrections: corrections
        )

        XCTAssertEqual(recap.headline, "Two things you said you’d do.")
    }

    func testSkippedRecurringFallsThroughCommitmentThenNeutralBranches() {
        let current = session("current", "2026-08-10T12:00:00Z")
        let earlier = session("earlier", "2026-08-01T12:00:00Z")
        let currentCommitment = item("current", sessionId: current.id, type: .commitment)
        let earlierItem = item("earlier", sessionId: earlier.id)
        let unreliable = topic(title: "Plans", itemIds: [currentCommitment.id, earlierItem.id, "missing"])

        let commitment = makeRecap(
            current: current,
            currentItems: [currentCommitment],
            sessions: [current, earlier],
            allItems: [currentCommitment, earlierItem],
            topics: [unreliable]
        )
        XCTAssertEqual(commitment.headline, "One thing you said you’d do.")

        let neutralItem = item("neutral", sessionId: current.id, type: .state)
        let neutral = makeRecap(current: current, currentItems: [neutralItem])
        XCTAssertEqual(neutral.headline, "1 thing worth remembering.")

        let empty = makeRecap(current: current, currentItems: [])
        XCTAssertEqual(empty.headline, "Nothing new was captured.")
    }

    func testQuoteSelectionIsCorrectedDeterministicNormalizedAndTruncated() {
        let current = session("current", "2026-08-10T12:00:00Z")
        let older = item(
            "older",
            sessionId: current.id,
            type: .intention,
            extractedAt: "2026-08-10T12:00:00Z",
            sourceQuote: "  older\n quote  "
        )
        let newest = item(
            "newest",
            sessionId: current.id,
            type: .state,
            extractedAt: "2026-08-10T12:01:00.500Z",
            sourceQuote: String(repeating: "word ", count: 30)
        )
        let corrections = [
            newest.id: ItemCorrection(itemId: newest.id, correctedType: ExtractedItem.ItemType.commitment)
        ]

        let quote = SessionRecapBuilder.selectedQuote(
            from: [older, newest],
            corrections: corrections
        )

        XCTAssertNotNil(quote)
        XCTAssertLessThanOrEqual(quote?.count ?? .max, 100)
        XCTAssertTrue(quote?.hasSuffix("…") == true)
        XCTAssertFalse(quote?.contains("  ") == true)
        XCTAssertEqual(quote?.dropLast().split(separator: " ").last, "word")
    }

    func testQuoteAtLimitDoesNotGainEllipsisAndUsesUserPerceivedCharacters() {
        let exact = String(repeating: "🙂", count: 100)
        XCTAssertEqual(SessionRecapBuilder.truncateQuote(exact, maximumCharacterCount: 100), exact)

        let truncated = SessionRecapBuilder.truncateQuote(
            String(repeating: "hello ", count: 30),
            maximumCharacterCount: 100
        )
        XCTAssertLessThanOrEqual(truncated.count, 100)
        XCTAssertTrue(truncated.hasSuffix("…"))
    }

    private func makeRecap(
        current: Session,
        currentItems: [ExtractedItem],
        sessions: [Session]? = nil,
        allItems: [ExtractedItem]? = nil,
        topics: [TopicAggregate] = [],
        corrections: [String: ItemCorrection] = [:],
        now: Date = Date(timeIntervalSince1970: 1_775_865_600)
    ) -> SessionRecap {
        SessionRecapBuilder.makeRecap(
            currentSession: current,
            currentItems: currentItems,
            allSessions: sessions ?? [current],
            allItems: allItems ?? currentItems,
            topics: topics,
            corrections: corrections,
            calendar: calendar,
            now: now
        )
    }

    private func session(_ id: String, _ startedAt: String) -> Session {
        Session(id: id, startedAt: date(startedAt), status: "complete")
    }

    private func item(
        _ id: String,
        sessionId: String,
        type: ItemType = .state,
        extractedAt: String = "2026-08-10T12:00:00Z",
        reviewState: String = ExtractedItem.ReviewState.new,
        sourceQuote: String = ""
    ) -> ExtractedItem {
        ExtractedItem(
            id: id,
            sessionId: sessionId,
            segmentId: "segment-\(id)",
            segmentIndex: 0,
            type: type.rawValue,
            title: "Title \(id)",
            summary: "Summary",
            categories: [ExtractedItem.Category.personalGrowth],
            confidence: 0.8,
            strength: 0.8,
            sourceQuote: sourceQuote,
            fingerprint: "fingerprint-\(id)",
            reviewState: reviewState,
            createdAt: extractedAt,
            extractedAt: extractedAt
        )
    }

    private func topic(title: String, itemIds: [String]) -> TopicAggregate {
        var topic = TopicAggregate(
            canonicalKey: "\(title.lowercased())__123456",
            displayTitle: title,
            firstSeenAtISO: "2026-08-01T00:00:00Z",
            categories: [ExtractedItem.Category.personalGrowth],
            itemId: itemIds.first ?? "",
            topicKey: "personal_growth|\(title.lowercased())"
        )
        topic.itemIds = itemIds
        topic.occurrenceCount = itemIds.count
        return topic
    }

    private func date(_ value: String) -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)!
    }

    private enum ItemType: String {
        case event
        case intention
        case commitment
        case state
    }
}
