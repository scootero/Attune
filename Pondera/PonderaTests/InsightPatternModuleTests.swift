import XCTest
@testable import Pondera

final class InsightPatternModuleTests: XCTestCase {
    func testRecurringThemeUsesVisibleEvidence() {
        let items = (1...3).map { index in
            makeItem(id: "item-\(index)", sessionID: "session-\(index)", date: "2026-08-\(20 + index)T12:00:00Z")
        }
        var topic = TopicAggregate(
            canonicalKey: "exercise__abc123",
            displayTitle: "Exercise",
            firstSeenAtISO: items[0].createdAt,
            categories: [ExtractedItem.Category.fitnessHealth],
            itemId: items[0].id
        )
        topic.addMention(from: items[1])
        topic.addMention(from: items[2])

        let patterns = InsightPatternBuilder.make(items: items, topics: [topic], moods: [])

        XCTAssertEqual(patterns.count, 1)
        XCTAssertEqual(patterns.first?.title, "Exercise keeps returning")
        XCTAssertEqual(patterns.first?.sampleSize, 3)
    }

    func testMoodThemePatternRequiresMeaningfulDifferenceAndEvidence() {
        let items = (1...3).map { index in
            makeItem(id: "item-\(index)", sessionID: "session-\(index)", date: "2026-08-\(20 + index)T12:00:00Z")
        }
        var topic = TopicAggregate(
            canonicalKey: "creative__abc123",
            displayTitle: "Creative Work",
            firstSeenAtISO: items[0].createdAt,
            categories: [ExtractedItem.Category.personalGrowth],
            itemId: items[0].id
        )
        topic.addMention(from: items[1])
        topic.addMention(from: items[2])

        let moods = (1...3).map { index in
            DailyMood(dateKey: "2026-08-\(20 + index)", moodScore: 9)
        } + [
            DailyMood(dateKey: "2026-08-19", moodScore: 4),
            DailyMood(dateKey: "2026-08-24", moodScore: 4)
        ]

        let patterns = InsightPatternBuilder.make(items: items, topics: [topic], moods: moods)

        XCTAssertEqual(patterns.first?.kind, .moodAndTheme)
        XCTAssertTrue(patterns.first?.title.contains("higher") ?? false)
    }

    func testIncorrectCaptureDoesNotContribute() {
        let item = makeItem(id: "hidden", sessionID: "session-1", date: "2026-08-21T12:00:00Z")
        let topic = TopicAggregate(
            canonicalKey: "hidden__abc123",
            displayTitle: "Hidden",
            firstSeenAtISO: item.createdAt,
            categories: [],
            itemId: item.id
        )

        let correction = ItemCorrection(itemId: item.id, isIncorrect: true)
        XCTAssertTrue(InsightPatternBuilder.make(items: [item], topics: [topic], moods: [], corrections: [item.id: correction]).isEmpty)
    }

    private func makeItem(id: String, sessionID: String, date: String) -> ExtractedItem {
        ExtractedItem(
            id: id,
            sessionId: sessionID,
            segmentId: "segment-\(id)",
            segmentIndex: 0,
            type: ExtractedItem.ItemType.state,
            title: "A capture",
            summary: "A summary",
            categories: [ExtractedItem.Category.personalGrowth],
            confidence: 0.9,
            strength: 0.8,
            sourceQuote: "A quote",
            fingerprint: "fingerprint-\(id)",
            createdAt: date,
            extractedAt: date
        )
    }
}
