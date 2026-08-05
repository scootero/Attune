//
//  SubscriptionManager.swift
//  Attune
//
//  StoreKit 2 helper: loads the monthly product, purchases, restores,
//  and tracks whether the user currently has an active subscription.
//

import Combine
import Foundation
import StoreKit

/// Owns StoreKit product + entitlement state for the rest of the UI.
@MainActor
final class SubscriptionManager: ObservableObject {

    /// Shared instance injected via environmentObject from ContentView.
    static let shared = SubscriptionManager()

    /// True when the user has an active Attune Pro monthly subscription.
    @Published private(set) var isSubscribed: Bool = false

    /// Loaded StoreKit product (nil until loaded or if ASC product is missing).
    @Published private(set) var product: Product?

    /// True while a purchase / restore / product load is in flight.
    @Published private(set) var isBusy: Bool = false

    /// True only while StoreKit product details are loading.
    @Published private(set) var isLoadingProduct: Bool = false

    /// True when StoreKit says this Apple ID can use the introductory free trial.
    @Published private(set) var isEligibleForIntroOffer: Bool = false

    /// User-facing error from the last failed purchase/restore/load.
    @Published var lastErrorMessage: String?

    /// Watches StoreKit transaction updates in the background.
    private var transactionListener: Task<Void, Never>?

    private init() {
        // Keep entitlement in sync when Apple delivers transaction updates.
        transactionListener = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(transactionUpdate: update)
            }
        }
        Task { await refresh() }
    }

    // MARK: - Public API

    /// Reloads product info and current entitlement from StoreKit.
    func refresh() async {
        guard !isLoadingProduct else { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        lastErrorMessage = nil
        await loadProduct()
        await refreshEntitlement()
    }

    /// Starts a purchase for the monthly subscription.
    func purchase() async {
        lastErrorMessage = nil
        guard let product = product else {
            lastErrorMessage = "Attune Pro isn’t available right now. Check your connection and try again."
            await loadProduct()
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlement()
            case .userCancelled:
                break
            case .pending:
                lastErrorMessage = "Purchase is pending approval."
            @unknown default:
                lastErrorMessage = "Purchase could not be completed."
            }
        } catch {
            lastErrorMessage = "The purchase couldn’t be completed. Please try again."
            AppLogger.log(AppLogger.ERR, "StoreKit purchase failed: \(error.localizedDescription)")
        }
    }

    /// Restores previous purchases (required by App Store guidelines).
    func restore() async {
        lastErrorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if !isSubscribed {
                lastErrorMessage = "No active subscription found for this Apple ID."
            }
        } catch {
            lastErrorMessage = "Purchases couldn’t be restored right now. Please try again."
            AppLogger.log(AppLogger.ERR, "StoreKit restore failed: \(error.localizedDescription)")
        }
    }

    /// Effective premium access for feature gates.
    /// Debug builds unlock everything so we can test on device without StoreKit/App Store Connect.
    /// Release builds still require a real subscription entitlement.
    var hasPremiumAccess: Bool {
        #if DEBUG
        return true
        #else
        return isSubscribed
        #endif
    }

    /// Free users get a daily check-in allowance; subscribers are unlimited.
    func canStartCheckIn(todayCheckInCount: Int) -> Bool {
        if hasPremiumAccess { return true }
        return todayCheckInCount < SubscriptionConfig.freeCheckInsPerDay
    }

    /// All-day recording is a subscriber feature.
    var canUseAllDayRecording: Bool { hasPremiumAccess }

    /// Voice “Record Intentions” is a subscriber feature (manual add stays free).
    var canUseVoiceIntentions: Bool { hasPremiumAccess }

    /// Free users may add their first intention; Pro users may use the app cap.
    func canAddIntention(currentCount: Int) -> Bool {
        if hasPremiumAccess { return currentCount < SubscriptionConfig.maximumActiveIntentions }
        return currentCount < SubscriptionConfig.freeActiveIntentionsLimit
    }

    /// Insights and historical views are subscriber features.
    var canUseInsights: Bool { hasPremiumAccess }

    /// Free includes today's Momentum only; history, Week, and Month require Pro.
    var canUseMomentumHistory: Bool { hasPremiumAccess }

    /// Portable data export is a subscriber feature.
    var canExportData: Bool { hasPremiumAccess }

    /// Price string from StoreKit when available, otherwise the known fallback.
    var priceText: String {
        if let product = product {
            return product.displayPrice + " / month"
        }
        return SubscriptionConfig.displayPriceFallback
    }

    // MARK: - Private

    private func loadProduct() async {
        do {
            let products = try await Product.products(for: [SubscriptionConfig.monthlyProductID])
            product = products.first
            if let subscription = product?.subscription {
                isEligibleForIntroOffer = await subscription.isEligibleForIntroOffer
            } else {
                isEligibleForIntroOffer = false
            }
            if product == nil {
                lastErrorMessage = "Attune Pro is temporarily unavailable. Please try again later."
            }
        } catch {
            product = nil
            isEligibleForIntroOffer = false
            lastErrorMessage = "Attune Pro couldn’t be loaded. Check your connection and try again."
            AppLogger.log(AppLogger.ERR, "StoreKit product load failed: \(error.localizedDescription)")
        }
    }

    private func refreshEntitlement() async {
        var hasActive = false
        // currentEntitlements includes active auto-renewable subscriptions.
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.productID == SubscriptionConfig.monthlyProductID {
                hasActive = true
                break
            }
        }
        isSubscribed = hasActive
    }

    private func handle(transactionUpdate: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerified(transactionUpdate) else { return }
        await transaction.finish()
        await refreshEntitlement()
    }

    /// Unwraps StoreKit’s verified transaction or throws if the payload is untrusted.
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.unverified
        case .verified(let safe):
            return safe
        }
    }
}

/// Local errors for subscription verification failures.
enum SubscriptionError: LocalizedError {
    case unverified

    var errorDescription: String? {
        switch self {
        case .unverified:
            return "Could not verify the App Store purchase."
        }
    }
}
