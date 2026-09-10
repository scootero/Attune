import XCTest
@testable import Pondera

final class SubscriptionAccessPolicyTests: XCTestCase {
    private let free = SubscriptionAccessPolicy(hasProAccess: false)
    private let pro = SubscriptionAccessPolicy(hasProAccess: true)

    func testFreeUserCanCreateFirstButNotSecondIntention() {
        XCTAssertTrue(free.canAddIntention(currentCount: 0))
        XCTAssertFalse(free.canAddIntention(currentCount: 1))
    }

    func testProUserCanCreateThroughProductCap() {
        XCTAssertTrue(pro.canAddIntention(currentCount: 1))
        XCTAssertTrue(pro.canAddIntention(currentCount: 9))
        XCTAssertFalse(pro.canAddIntention(currentCount: 10))
    }

    func testFreeFinalSaveAllowsOneActiveIntention() {
        XCTAssertTrue(free.canSaveIntentions(baselineIDs: [], proposedIDs: ["first"]))
        XCTAssertFalse(free.canSaveIntentions(baselineIDs: ["first"], proposedIDs: ["first", "second"]))
    }

    func testRemovedOrArchivedIntentionDoesNotConsumeSlot() {
        XCTAssertTrue(free.canSaveIntentions(baselineIDs: ["archived"], proposedIDs: ["replacement"]))
        XCTAssertTrue(free.canSaveIntentions(baselineIDs: ["removed"], proposedIDs: []))
    }

    func testDowngradedUserCanKeepEditAndRemoveExistingIntentions() {
        let existing: Set<String> = ["one", "two", "three"]
        XCTAssertTrue(free.canSaveIntentions(baselineIDs: existing, proposedIDs: ["one", "two", "three"]))
        XCTAssertTrue(free.canSaveIntentions(baselineIDs: existing, proposedIDs: ["one", "two"]))
        XCTAssertTrue(free.canSaveIntentions(baselineIDs: existing, proposedIDs: ["replacement"]))
    }

    func testDowngradedUserCannotIntroduceNewIDWhileRemainingOverLimit() {
        let existing: Set<String> = ["one", "two"]
        XCTAssertFalse(free.canSaveIntentions(baselineIDs: existing, proposedIDs: ["one", "replacement"]))
        XCTAssertFalse(free.canSaveIntentions(baselineIDs: existing, proposedIDs: ["one", "two", "three"]))
    }

    func testDuplicateIDsAndProductCapAreRejected() {
        XCTAssertFalse(pro.canSaveIntentions(baselineIDs: [], proposedIDs: ["same", "same"]))
        let eleven = (0..<11).map(String.init)
        XCTAssertFalse(pro.canSaveIntentions(baselineIDs: [], proposedIDs: eleven))
    }

    func testListeningSessionsAndOtherExistingGates() {
        XCTAssertFalse(free.canUseListeningSessions)
        XCTAssertTrue(pro.canUseListeningSessions)
        XCTAssertFalse(free.canUseVoiceIntentions)
        XCTAssertTrue(pro.canUseVoiceIntentions)
        XCTAssertTrue(free.canStartCheckIn(todayCheckInCount: 0))
        XCTAssertFalse(free.canStartCheckIn(todayCheckInCount: 1))
        XCTAssertTrue(pro.canStartCheckIn(todayCheckInCount: 20))
    }
}

