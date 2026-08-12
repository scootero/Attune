import XCTest
@testable import Attune

final class AIUsageLimitTests: XCTestCase {
    func testUsageStatusDecodesResetAndLimit() throws {
        let data = Data(#"{
          "usedUnits": 8000000,
          "limitUnits": 10000000,
          "warningAtUnits": 8000000,
          "warning": true,
          "limited": false,
          "resetsAt": "2026-09-01T00:00:00.000Z",
          "period": "2026-08"
        }"#.utf8)

        let status = try JSONDecoder().decode(AIUsageStatus.self, from: data)
        XCTAssertEqual(status.period, "2026-08")
        XCTAssertEqual(status.limitUnits, 10_000_000)
        XCTAssertTrue(status.warning)
        XCTAssertFalse(status.limited)
        XCTAssertNotNil(status.resetDate)
    }

    func testLimitNoticeKeepsSavedDataReassurance() {
        let notice = AIUsageNotice(kind: .limited, resetDate: nil)
        XCTAssertEqual(notice.title, "Monthly AI limit reached")
        XCTAssertTrue(notice.message.contains("Everything already saved in Attune is still available"))
        XCTAssertTrue(notice.message.contains("refreshes next month"))
    }

    func testWarningNoticeDoesNotClaimUserIsBlocked() {
        let notice = AIUsageNotice(kind: .warning, resetDate: nil)
        XCTAssertEqual(notice.title, "AI allowance running low")
        XCTAssertTrue(notice.message.contains("nearing"))
        XCTAssertFalse(notice.message.contains("limit reached"))
    }
}
