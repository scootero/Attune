import XCTest
@testable import Pondera

final class EditIntentionsDraftTests: XCTestCase {
    func testSeparateBlankAddDraftsAreNotTreatedAsUserChanges() {
        let current = DraftIntention.empty()
        let baseline = DraftIntention.empty()

        XCTAssertNotEqual(current.id, baseline.id)
        XCTAssertFalse(current.hasEditableChanges(comparedTo: baseline))
    }

    func testEnteredAddDraftIsTreatedAsUserChange() {
        var current = DraftIntention.empty()
        let baseline = DraftIntention.empty()
        current.title = "Walk"

        XCTAssertTrue(current.hasEditableChanges(comparedTo: baseline))
    }

    func testTimeframeComparisonIsCaseInsensitive() {
        var current = DraftIntention.empty()
        var baseline = DraftIntention.empty()
        current.timeframe = "Daily"
        baseline.timeframe = "daily"

        XCTAssertFalse(current.hasEditableChanges(comparedTo: baseline))
    }
}
