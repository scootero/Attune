import StoreKit
import StoreKitTest
import XCTest
@testable import Pondera

final class BrandMigrationTests: XCTestCase {
    func testHostAppUsesPonderaIdentity() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.scottoliver.Pondera.Intentions")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Pondera")
    }

    func testSubscriptionUsesPonderaProductID() {
        XCTAssertEqual(SubscriptionConfig.monthlyProductID, "com.scottoliver.Pondera.Intentions.monthly")
        XCTAssertEqual(SubscriptionConfig.displayName, "Pondera Pro")
    }

    func testLocalStoreKitConfigurationLoadsPonderaProduct() async throws {
        let session = try SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = true
        session.clearTransactions()

        let products = try await Product.products(for: [SubscriptionConfig.monthlyProductID])

        XCTAssertEqual(products.map(\.id), [SubscriptionConfig.monthlyProductID])
        XCTAssertEqual(products.first?.displayPrice, "$4.99")
    }
}
