import XCTest
@testable import Pondera

@MainActor
final class EngagementMetricsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testReviewEligibilityRequiresAgeCountAndDistinctDays() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 15)))
        let installedAt = try XCTUnwrap(calendar.date(byAdding: .day, value: -8, to: now))
        var snapshot = EngagementMetricsSnapshot(installedAt: installedAt, lastUpdatedAt: now)
        snapshot.lifetime.checkInsCompleted = 4
        snapshot.daily = [
            "2026-08-10": countersWithCompletedCheckIns(2),
            "2026-08-12": countersWithCompletedCheckIns(1),
            "2026-08-15": countersWithCompletedCheckIns(1)
        ]

        XCTAssertTrue(
            AppReviewEligibilityPolicy.isEligible(
                snapshot: snapshot,
                currentVersion: "1.0",
                now: now,
                calendar: calendar
            )
        )

        snapshot.daily.removeValue(forKey: "2026-08-12")
        XCTAssertFalse(
            AppReviewEligibilityPolicy.isEligible(
                snapshot: snapshot,
                currentVersion: "1.0",
                now: now,
                calendar: calendar
            )
        )
    }

    func testReviewEligibilityIsOncePerVersionAndRespectsCooldown() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 15)))
        let installedAt = try XCTUnwrap(calendar.date(byAdding: .day, value: -30, to: now))
        var snapshot = eligibleSnapshot(installedAt: installedAt, now: now)
        snapshot.review.lastRequestedVersion = "1.0"
        snapshot.review.lastRequestDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -20, to: now))

        XCTAssertFalse(
            AppReviewEligibilityPolicy.isEligible(
                snapshot: snapshot,
                currentVersion: "1.0",
                now: now,
                calendar: calendar
            )
        )
        XCTAssertTrue(
            AppReviewEligibilityPolicy.isEligible(
                snapshot: snapshot,
                currentVersion: "1.1",
                now: now,
                calendar: calendar
            )
        )

        snapshot.review.lastRequestDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -5, to: now))
        XCTAssertFalse(
            AppReviewEligibilityPolicy.isEligible(
                snapshot: snapshot,
                currentVersion: "1.1",
                now: now,
                calendar: calendar
            )
        )
    }

    func testStoreDeduplicatesPersistentCompletionEvents() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PonderaEngagementMetricsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 15)))
        let store = EngagementMetricsStore(
            fileURL: temporaryDirectory.appendingPathComponent("EngagementMetrics.json"),
            calendar: calendar,
            now: { now }
        )

        store.record(.checkInCompleted, eventID: "check-in-completed:abc")
        store.record(.checkInCompleted, eventID: "check-in-completed:abc")

        let snapshot = store.loadSnapshot()
        XCTAssertEqual(snapshot.lifetime.checkInsCompleted, 1)
        XCTAssertEqual(snapshot.checkInDayCount, 1)
    }

    private func eligibleSnapshot(installedAt: Date, now: Date) -> EngagementMetricsSnapshot {
        var snapshot = EngagementMetricsSnapshot(installedAt: installedAt, lastUpdatedAt: now)
        snapshot.lifetime.checkInsCompleted = 4
        snapshot.daily = [
            "2026-08-10": countersWithCompletedCheckIns(2),
            "2026-08-12": countersWithCompletedCheckIns(1),
            "2026-08-15": countersWithCompletedCheckIns(1)
        ]
        return snapshot
    }

    private func countersWithCompletedCheckIns(_ count: Int) -> EngagementCounters {
        var counters = EngagementCounters()
        counters.checkInsCompleted = count
        return counters
    }
}
