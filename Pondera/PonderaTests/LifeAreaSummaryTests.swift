import XCTest
@testable import Pondera

final class LifeAreaSummaryTests: XCTestCase {
    func testCategoriesCountDistinctSessionsAndSortBySessionCount() {
        let items = [
            makeItem(id: "one", sessionID: "session-a", categories: [ExtractedItem.Category.moneyFinance, ExtractedItem.Category.moneyFinance]),
            makeItem(id: "two", sessionID: "session-a", categories: [ExtractedItem.Category.moneyFinance, ExtractedItem.Category.careerWork]),
            makeItem(id: "three", sessionID: "session-b", categories: [ExtractedItem.Category.careerWork])
        ]

        let summaries = LifeAreaSummaryBuilder.make(from: items)

        XCTAssertEqual(summaries.map(\.category), [ExtractedItem.Category.careerWork, ExtractedItem.Category.moneyFinance])
        XCTAssertEqual(summaries.first?.mentionCount, 2)
        XCTAssertEqual(summaries.first?.sessionCount, 2)
        XCTAssertEqual(summaries.last?.mentionCount, 2)
        XCTAssertEqual(summaries.last?.sessionCount, 1)
    }

    func testIncorrectCaptureDoesNotContributeToLifeArea() {
        let item = makeItem(id: "hidden", sessionID: "session-a", categories: [ExtractedItem.Category.personalGrowth])
        let correction = ItemCorrection(itemId: item.id, isIncorrect: true)

        XCTAssertTrue(LifeAreaSummaryBuilder.make(from: [item], corrections: [item.id: correction]).isEmpty)
    }

    func testDayPeriodOnlyIncludesCapturesFromReferenceDay() throws {
        let referenceDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-29T18:00:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let items = [
            makeItem(
                id: "today",
                sessionID: "session-a",
                categories: [ExtractedItem.Category.careerWork],
                createdAt: "2026-08-29T12:00:00Z"
            ),
            makeItem(
                id: "yesterday",
                sessionID: "session-b",
                categories: [ExtractedItem.Category.moneyFinance],
                createdAt: "2026-08-28T12:00:00Z"
            )
        ]

        let summaries = LifeAreaSummaryBuilder.make(
            from: items,
            period: .day,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(summaries.map(\.category), [ExtractedItem.Category.careerWork])
    }

    func testIntentionCountUsesCorrectedDisplayType() {
        let item = makeItem(
            id: "corrected",
            sessionID: "session-a",
            categories: [ExtractedItem.Category.personalGrowth]
        )
        let correction = ItemCorrection(
            itemId: item.id,
            correctedType: ExtractedItem.ItemType.intention
        )

        let summary = LifeAreaSummaryBuilder.make(
            from: [item],
            corrections: [item.id: correction]
        ).first

        XCTAssertEqual(summary?.intentionCount, 1)
    }

    func testLifeAreaBubbleScaleKeepsLowCountsDistinctAndHighCountsUnbounded() {
        XCTAssertEqual(LifeAreaBubbleScale.diameter(for: 1), 14)
        XCTAssertEqual(LifeAreaBubbleScale.diameter(for: 2), 22)
        XCTAssertEqual(LifeAreaBubbleScale.diameter(for: 3), 32)
        XCTAssertEqual(LifeAreaBubbleScale.diameter(for: 4), 44)
        XCTAssertEqual(LifeAreaBubbleScale.diameter(for: 5), 58)
        XCTAssertEqual(LifeAreaBubbleScale.diameter(for: 6), 63)
        XCTAssertEqual(LifeAreaBubbleScale.diameter(for: 10), 83)
        XCTAssertEqual(LifeAreaBubbleScale.diameter(for: 20), 133)
        XCTAssertEqual(LifeAreaBubbleScale.diameter(for: 50), 283)
    }

    private func makeItem(
        id: String,
        sessionID: String,
        categories: [String],
        type: String = ExtractedItem.ItemType.state,
        createdAt: String = "2026-08-29T12:00:00Z"
    ) -> ExtractedItem {
        ExtractedItem(
            id: id,
            sessionId: sessionID,
            segmentId: "segment-\(id)",
            segmentIndex: 0,
            type: type,
            title: "A capture",
            summary: "A summary",
            categories: categories,
            confidence: 0.9,
            strength: 0.8,
            sourceQuote: "A quote",
            contextBefore: nil,
            contextAfter: nil,
            fingerprint: "fingerprint-\(id)",
            reviewState: ExtractedItem.ReviewState.new,
            reviewedAt: nil,
            calendarCandidate: nil,
            createdAt: createdAt,
            extractedAt: createdAt
        )
    }
}
