import XCTest
@testable import Pondera

final class InsightIntentionPatternTests: XCTestCase {
    func testMoodIsAssociatedWithIntentionProgressDays() {
        let intention = Intention(id: "walk", title: "Walk", targetValue: 20, unit: "minutes", timeframe: "daily")
        let dates = ["2026-08-21", "2026-08-22", "2026-08-23"]
        let progress = dates.map { date in
            ProgressEntry(
                dateKey: date,
                intentionSetId: "set",
                intentionId: intention.id,
                updateType: "INCREMENT",
                amount: 20,
                unit: "minutes",
                confidence: 1,
                sourceCheckInId: "check-in-\(date)"
            )
        }
        let moods = dates.map { DailyMood(dateKey: $0, moodScore: 9) } + [
            DailyMood(dateKey: "2026-08-20", moodScore: 4),
            DailyMood(dateKey: "2026-08-24", moodScore: 4)
        ]

        let patterns = InsightPatternBuilder.makeIntentionPatterns(
            intentions: [intention], progressEntries: progress, moods: moods
        )

        XCTAssertEqual(patterns.count, 1)
        XCTAssertTrue(patterns[0].title.contains("higher"))
        XCTAssertEqual(patterns[0].sampleSize, 3)
    }
}
