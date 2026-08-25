import XCTest
@testable import Attune

final class BrandMigrationTests: XCTestCase {
    func testHostAppUsesPonderaIdentity() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.scottoliver.Pondera.Intentions")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Pondera")
    }

    func testPermanentSubscriptionProductIDIsRetained() {
        XCTAssertEqual(SubscriptionConfig.monthlyProductID, "com.scottoliver.Attune.monthly")
        XCTAssertEqual(SubscriptionConfig.displayName, "Pondera Pro")
    }
}
