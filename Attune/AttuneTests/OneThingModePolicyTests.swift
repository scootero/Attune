import XCTest
@testable import Attune

final class OneThingModePolicyTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testActivatesAfterTwoCompleteQuietDays() {
        XCTAssertTrue(OneThingModePolicy.shouldActivate(
            state: .empty,
            intentionSetStartedAt: date("2026-08-01T12:00:00Z"),
            activeIntentionCount: 2,
            activityDateKeys: [],
            calendar: calendar,
            now: date("2026-08-05T00:01:00Z")
        ))
    }

    func testEligibilityDoesNotBeginWithoutIntentionsAndUsesNewestActiveIntention() {
        let setStart = date("2026-08-01T00:00:00Z")
        XCTAssertNil(OneThingModePolicy.eligibilityStart(intentionSetStartedAt: setStart, intentions: []))

        let first = Intention(
            id: "first",
            title: "First",
            targetValue: 1,
            unit: "times",
            timeframe: "daily",
            createdAt: date("2026-08-03T08:00:00Z")
        )
        let second = Intention(
            id: "second",
            title: "Second",
            targetValue: 1,
            unit: "times",
            timeframe: "daily",
            createdAt: date("2026-08-05T09:00:00Z")
        )

        XCTAssertEqual(
            OneThingModePolicy.eligibilityStart(
                intentionSetStartedAt: setStart,
                intentions: [first, second]
            ),
            second.createdAt
        )
    }

    func testDoesNotActivateWithActivityOnEitherDayOrOnlyOneIntention() {
        for key in ["2026-08-03", "2026-08-04"] {
            XCTAssertFalse(OneThingModePolicy.shouldActivate(
                state: .empty,
                intentionSetStartedAt: date("2026-08-01T00:00:00Z"),
                activeIntentionCount: 2,
                activityDateKeys: [key],
                calendar: calendar,
                now: date("2026-08-05T12:00:00Z")
            ))
        }
        XCTAssertFalse(OneThingModePolicy.shouldActivate(state: .empty, intentionSetStartedAt: date("2026-08-01T00:00:00Z"), activeIntentionCount: 1, activityDateKeys: [], calendar: calendar, now: date("2026-08-05T12:00:00Z")))
    }

    func testExitRequiresTwoNewFullQuietDays() {
        let state = OneThingModeState(focusedIntentionId: nil, activatedAt: nil, lastExitedAt: date("2026-08-04T12:00:00Z"))
        XCTAssertFalse(OneThingModePolicy.shouldActivate(state: state, intentionSetStartedAt: date("2026-08-01T00:00:00Z"), activeIntentionCount: 3, activityDateKeys: [], calendar: calendar, now: date("2026-08-06T12:00:00Z")))
        XCTAssertTrue(OneThingModePolicy.shouldActivate(state: state, intentionSetStartedAt: date("2026-08-01T00:00:00Z"), activeIntentionCount: 3, activityDateKeys: [], calendar: calendar, now: date("2026-08-07T00:01:00Z")))
    }

    func testReplacementPrefersFirstZeroThenLowestAverage() {
        let first = intention("first")
        let second = intention("second")
        let third = intention("third")
        XCTAssertEqual(OneThingModePolicy.replacementCandidate(intentions: [first, second, third], dailyTotals: [first.id: [2, 2], second.id: [0, 0], third.id: [0, 0]])?.id, second.id)
        XCTAssertEqual(OneThingModePolicy.replacementCandidate(intentions: [first, second], dailyTotals: [first.id: [8, 8], second.id: [2, 4]])?.id, second.id)
    }

    @MainActor
    func testStoreActivationSwitchAndExitAreReversible() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = directory.appendingPathComponent("one-thing.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OneThingModeStore(fileURL: file)
        try store.activate(focusedIntentionId: "first", now: date("2026-08-05T00:00:00Z"))
        XCTAssertEqual(store.load().focusedIntentionId, "first")
        try store.select("second")
        XCTAssertEqual(store.load().focusedIntentionId, "second")
        try store.exit(now: date("2026-08-05T01:00:00Z"))
        XCTAssertFalse(store.load().isActive)
        XCTAssertEqual(store.load().lastExitedAt, date("2026-08-05T01:00:00Z"))
    }

    private func intention(_ id: String) -> Intention { Intention(id: id, title: id, targetValue: 10, unit: "times", timeframe: "daily") }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
}
