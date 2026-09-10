//
//  SubscriptionStoreClient.swift
//  Pondera
//
//  Small StoreKit boundary so subscription behavior can be tested deterministically.
//

import StoreKit

struct SubscriptionProductDetails: Equatable, Sendable {
    let displayPrice: String
}

enum SubscriptionPurchaseOutcome: Equatable, Sendable {
    case purchased
    case pending
    case cancelled
}

@MainActor
protocol SubscriptionStoreClient: AnyObject {
    func loadMonthlyProduct() async throws -> SubscriptionProductDetails?
    func purchaseMonthlyProduct() async throws -> SubscriptionPurchaseOutcome
    func restorePurchases() async throws
    func hasCurrentMonthlyEntitlement() async -> Bool
}

@MainActor
final class LiveSubscriptionStoreClient: SubscriptionStoreClient {
    private var monthlyProduct: Product?

    func loadMonthlyProduct() async throws -> SubscriptionProductDetails? {
        let products = try await Product.products(for: [SubscriptionConfig.monthlyProductID])
        monthlyProduct = products.first
        return monthlyProduct.map { SubscriptionProductDetails(displayPrice: $0.displayPrice) }
    }

    func purchaseMonthlyProduct() async throws -> SubscriptionPurchaseOutcome {
        guard let monthlyProduct else {
            throw SubscriptionError.productUnavailable
        }

        switch try await monthlyProduct.purchase() {
        case .success(let verification):
            let transaction = try verified(verification)
            await transaction.finish()
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            throw SubscriptionError.unknownPurchaseResult
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
    }

    func hasCurrentMonthlyEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verified(result) else { continue }
            if transaction.productID == SubscriptionConfig.monthlyProductID {
                return true
            }
        }
        return false
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.unverified
        case .verified(let safe):
            return safe
        }
    }
}

