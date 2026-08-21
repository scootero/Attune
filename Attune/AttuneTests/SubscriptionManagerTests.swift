import XCTest
@testable import Attune

@MainActor
final class SubscriptionManagerTests: XCTestCase {
    func testSuccessfulPurchaseUnlocksSystemEntitlement() async {
        let store = FakeSubscriptionStoreClient()
        let manager = makeManager(store)
        manager.debugMode = .system

        await manager.refresh()
        await manager.purchase()

        XCTAssertTrue(manager.isSubscribed)
        XCTAssertTrue(manager.hasPremiumAccess)
        XCTAssertEqual(manager.actionState, .purchased)
    }

    func testRestoreUnlocksActiveEntitlement() async {
        let store = FakeSubscriptionStoreClient()
        store.entitlementAfterRestore = true
        let manager = makeManager(store)
        manager.debugMode = .system

        await manager.restore()

        XCTAssertTrue(manager.isSubscribed)
        XCTAssertEqual(manager.actionState, .restored)
    }

    func testRestoreWithoutEntitlementStaysUsable() async {
        let store = FakeSubscriptionStoreClient()
        let manager = makeManager(store)

        await manager.restore()

        XCTAssertFalse(manager.isSubscribed)
        XCTAssertEqual(manager.actionState, .noActiveSubscription)
        XCTAssertFalse(manager.isBusy)
    }

    func testPendingAndCancelledPurchasesStayUsable() async {
        let store = FakeSubscriptionStoreClient()
        let manager = makeManager(store)
        await manager.refresh()

        store.purchaseOutcome = .pending
        await manager.purchase()
        XCTAssertEqual(manager.actionState, .pending)
        XCTAssertFalse(manager.isBusy)

        store.purchaseOutcome = .cancelled
        await manager.purchase()
        XCTAssertEqual(manager.actionState, .cancelled)
        XCTAssertFalse(manager.isBusy)
    }

    func testPurchaseAndRestoreFailuresStayUsable() async {
        let store = FakeSubscriptionStoreClient()
        let manager = makeManager(store)
        await manager.refresh()

        store.purchaseError = TestError.expected
        await manager.purchase()
        XCTAssertTrue(manager.actionState.isFailure)
        XCTAssertFalse(manager.isBusy)

        store.purchaseError = nil
        store.restoreError = TestError.expected
        await manager.restore()
        XCTAssertTrue(manager.actionState.isFailure)
        XCTAssertFalse(manager.isBusy)
    }

    func testEntitlementRefreshRemovesFutureProAccessWithoutTouchingData() async {
        let store = FakeSubscriptionStoreClient()
        store.hasEntitlement = true
        let manager = makeManager(store)
        manager.debugMode = .system

        await manager.refreshEntitlement()
        XCTAssertTrue(manager.hasPremiumAccess)

        store.hasEntitlement = false
        await manager.refreshEntitlement()
        XCTAssertFalse(manager.hasPremiumAccess)
        XCTAssertEqual(store.destructiveOperationCount, 0)
    }

    func testDebugModesAreIndependentOfStoreEntitlement() async {
        let store = FakeSubscriptionStoreClient()
        store.hasEntitlement = false
        let manager = makeManager(store)

        manager.debugMode = .pro
        XCTAssertTrue(manager.hasPremiumAccess)
        manager.debugMode = .free
        XCTAssertFalse(manager.hasPremiumAccess)
        manager.debugMode = .system
        XCTAssertFalse(manager.hasPremiumAccess)
    }

    func testDuplicatePurchaseCallIsIgnoredWhileBusy() async {
        let store = FakeSubscriptionStoreClient()
        store.purchaseDelayNanoseconds = 100_000_000
        let manager = makeManager(store)
        await manager.refresh()

        let first = Task { await manager.purchase() }
        await Task.yield()
        await manager.purchase()
        await first.value

        XCTAssertEqual(store.purchaseCallCount, 1)
    }

    private func makeManager(_ store: FakeSubscriptionStoreClient) -> SubscriptionManager {
        SubscriptionManager(
            storeClient: store,
            listenForTransactions: false,
            automaticallyRefresh: false,
            persistsDebugModeChanges: false
        )
    }
}

@MainActor
private final class FakeSubscriptionStoreClient: SubscriptionStoreClient {
    var productDetails: SubscriptionProductDetails? = .init(displayPrice: "$4.99")
    var purchaseOutcome: SubscriptionPurchaseOutcome = .purchased
    var purchaseError: Error?
    var restoreError: Error?
    var hasEntitlement = false
    var entitlementAfterRestore = false
    var purchaseCallCount = 0
    var destructiveOperationCount = 0
    var purchaseDelayNanoseconds: UInt64 = 0

    func loadMonthlyProduct() async throws -> SubscriptionProductDetails? {
        productDetails
    }

    func purchaseMonthlyProduct() async throws -> SubscriptionPurchaseOutcome {
        purchaseCallCount += 1
        if purchaseDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: purchaseDelayNanoseconds)
        }
        if let purchaseError { throw purchaseError }
        if purchaseOutcome == .purchased { hasEntitlement = true }
        return purchaseOutcome
    }

    func restorePurchases() async throws {
        if let restoreError { throw restoreError }
        hasEntitlement = entitlementAfterRestore
    }

    func hasCurrentMonthlyEntitlement() async -> Bool {
        hasEntitlement
    }
}

private enum TestError: Error {
    case expected
}
