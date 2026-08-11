import XCTest
@testable import Attune

final class DailyReminderCopyTests: XCTestCase {
    func testReminderUsesApprovedNeutralCopy() {
        XCTAssertEqual(DailyReminderCopy.title, "A quick check-in")
        XCTAssertEqual(DailyReminderCopy.body, "Anything you'd like to log today?")
    }

    func testReminderCopyDoesNotExposeProgressOrPrivateQuotes() {
        let visibleCopy = "\(DailyReminderCopy.title) \(DailyReminderCopy.body)"

        XCTAssertFalse(visibleCopy.contains("%"))
        XCTAssertFalse(visibleCopy.localizedCaseInsensitiveContains("You said"))
        XCTAssertFalse(visibleCopy.localizedCaseInsensitiveContains("only at"))
    }
}
