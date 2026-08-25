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
}
