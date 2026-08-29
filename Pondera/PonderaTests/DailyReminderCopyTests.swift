import XCTest
@testable import Pondera

final class DailyReminderCopyTests: XCTestCase {
    func testReminderUsesRequestedBrandAndProgressPrompt() {
        XCTAssertEqual(DailyReminderCopy.title, "Pondera — Let’s make some progress")
        XCTAssertEqual(
            DailyReminderCopy.body(intentionTitles: ["Walk", "Read", "Meditate"]),
            "What would you like to move forward? Walk • Read"
        )
    }

    func testPolicyOnlyNotifiesWhenNoProgressWasUpdated() {
        XCTAssertTrue(DailyReminderPolicy.shouldNotify(
            hasActiveIntentions: true,
            progressEntryCount: 0,
            manualProgressUpdateCount: 0
        ))
        XCTAssertFalse(DailyReminderPolicy.shouldNotify(
            hasActiveIntentions: true,
            progressEntryCount: 1,
            manualProgressUpdateCount: 0
        ))
        XCTAssertFalse(DailyReminderPolicy.shouldNotify(
            hasActiveIntentions: true,
            progressEntryCount: 0,
            manualProgressUpdateCount: 1
        ))
        XCTAssertFalse(DailyReminderPolicy.shouldNotify(
            hasActiveIntentions: false,
            progressEntryCount: 0,
            manualProgressUpdateCount: 0
        ))
    }

    func testFollowUpCopyCanNameSelectedIntention() {
        XCTAssertEqual(DailyReminderCopy.followUpBody(intentionTitle: "Walk"), "Ready to update Walk?")
        XCTAssertEqual(DailyReminderCopy.followUpBody(intentionTitle: nil), "Ready to update one of today’s intentions?")
    }

    func testNotificationNudgeOnlyShowsForEnabledReminderWithoutAccess() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertTrue(NotificationPermissionNudgePolicy.shouldShow(
            reminderEnabled: true,
            authorizationStatus: .denied,
            lastShownAt: nil,
            now: now
        ))
        XCTAssertFalse(NotificationPermissionNudgePolicy.shouldShow(
            reminderEnabled: false,
            authorizationStatus: .denied,
            lastShownAt: nil,
            now: now
        ))
        XCTAssertFalse(NotificationPermissionNudgePolicy.shouldShow(
            reminderEnabled: true,
            authorizationStatus: .authorized,
            lastShownAt: nil,
            now: now
        ))
    }

    func testNotificationNudgeWaitsTwoDaysAfterBeingShown() {
        let shown = Date(timeIntervalSince1970: 10_000)
        XCTAssertFalse(NotificationPermissionNudgePolicy.shouldShow(
            reminderEnabled: true,
            authorizationStatus: .notDetermined,
            lastShownAt: shown,
            now: shown.addingTimeInterval(60 * 60 * 24 * 2 - 1)
        ))
        XCTAssertTrue(NotificationPermissionNudgePolicy.shouldShow(
            reminderEnabled: true,
            authorizationStatus: .notDetermined,
            lastShownAt: shown,
            now: shown.addingTimeInterval(60 * 60 * 24 * 2)
        ))
    }
}
