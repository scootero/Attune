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
        XCTAssertEqual(SubscriptionConfig.lifetimeProductID, "com.scottoliver.Pondera.Intentions.lifetime")
        XCTAssertEqual(
            SubscriptionConfig.proProductIDs,
            [SubscriptionConfig.monthlyProductID, SubscriptionConfig.lifetimeProductID]
        )
        XCTAssertEqual(SubscriptionConfig.displayName, "Pondera Pro")
    }

    func testLocalStoreKitConfigurationLoadsPonderaProduct() async throws {
        let session = try SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = true
        session.clearTransactions()

        let products = try await Product.products(for: Array(SubscriptionConfig.proProductIDs))
        let productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })

        XCTAssertEqual(Set(products.map(\.id)), SubscriptionConfig.proProductIDs)
        XCTAssertEqual(productsByID[SubscriptionConfig.monthlyProductID]?.displayPrice, "$3.99")
        XCTAssertEqual(productsByID[SubscriptionConfig.lifetimeProductID]?.type, .nonConsumable)
    }
}
