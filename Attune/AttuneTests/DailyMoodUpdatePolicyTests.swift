import XCTest
@testable import Attune

private struct LegacyDailyMoodFixture: Encodable {
    let dateKey: String
    let moodLabel: String?
    let moodScore: Int?
    let updatedAt: Date
    let sourceCheckInId: String?
    let isManualOverride: Bool
}

final class DailyMoodUpdatePolicyTests: XCTestCase {
    func testLatestObservationWinsRegardlessOfProcessingTime() {
        let earlier = Date(timeIntervalSince1970: 100)
        let later = Date(timeIntervalSince1970: 200)
        let existing = DailyMood(
            dateKey: "2026-08-20",
            moodLabel: "Calm",
            moodScore: 7,
            updatedAt: Date(timeIntervalSince1970: 300),
            observedAt: later,
            source: .manual,
            isManualOverride: true
        )

        XCTAssertFalse(DailyMoodUpdatePolicy.shouldReplace(existing: existing, observedAt: earlier))
        XCTAssertTrue(DailyMoodUpdatePolicy.shouldReplace(existing: existing, observedAt: later))
        XCTAssertTrue(
            DailyMoodUpdatePolicy.shouldReplace(
                existing: existing,
                observedAt: Date(timeIntervalSince1970: 201)
            )
        )
    }

    func testLegacyRecordUsesUpdatedAtAsOrderingFallback() {
        let existing = DailyMood(
            dateKey: "2026-08-20",
            moodLabel: "Okay",
            moodScore: 5,
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertFalse(
            DailyMoodUpdatePolicy.shouldReplace(
                existing: existing,
                observedAt: Date(timeIntervalSince1970: 199)
            )
        )
    }

    func testCurrentLowScoresAreClampedWithoutLegacyRemapping() {
        XCTAssertEqual(DailyMoodStore.clampMoodScore(0), 0)
        XCTAssertEqual(DailyMoodStore.clampMoodScore(1), 1)
        XCTAssertEqual(DailyMoodStore.clampMoodScore(2), 2)
        XCTAssertEqual(DailyMoodStore.clampMoodScore(-1), 0)
        XCTAssertEqual(DailyMoodStore.clampMoodScore(11), 10)
    }

    func testExistingDailyMoodFilesDecodeWithoutNewProvenanceFields() throws {
        let fixture = LegacyDailyMoodFixture(
            dateKey: "2026-08-20",
            moodLabel: "Calm",
            moodScore: 7,
            updatedAt: Date(timeIntervalSince1970: 200),
            sourceCheckInId: "check-in-1",
            isManualOverride: false
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(DailyMood.self, from: encoder.encode(fixture))

        XCTAssertNil(decoded.observedAt)
        XCTAssertNil(decoded.source)
        XCTAssertEqual(decoded.sourceCheckInId, "check-in-1")
        XCTAssertEqual(decoded.effectiveObservedAt, fixture.updatedAt)
    }
}
