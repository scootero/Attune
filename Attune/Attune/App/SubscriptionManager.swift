//
//  SubscriptionManager.swift
//  Attune
//
//  StoreKit 2 subscription state and the single source for feature access.
//

import Combine
import Foundation
import StoreKit

enum SubscriptionActionState: Equatable {
    case idle
    case purchasing
    case purchased
    case pending
    case cancelled
    case restoring
    case restored
    case noActiveSubscription
    case failed(String)

    var message: String? {
        switch self {
        case .idle, .purchasing, .restoring:
            return nil
        case .purchased:
            return "Attune Pro is active."
        case .pending:
            return "Purchase is pending approval. Pro will unlock when Apple completes it."
        case .cancelled:
            return "Purchase cancelled. You can continue using Attune Free."
        case .restored:
            return "Attune Pro was restored."
        case .noActiveSubscription:
            return "No active subscription was found for this Apple ID."
        case .failed(let message):
            return message
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

#if DEBUG
enum DebugSubscriptionMode: String, CaseIterable, Identifiable {
    case pro
    case free
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pro: return "Pro"
        case .free: return "Free"
        case .system: return "System"
        }
    }
}
#endif

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    @Published private(set) var isSubscribed = false
    @Published private(set) var productDetails: SubscriptionProductDetails?
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var actionState: SubscriptionActionState = .idle

    #if DEBUG
    @Published var debugMode: DebugSubscriptionMode {
        didSet {
            if persistsDebugModeChanges {
                UserDefaults.standard.set(debugMode.rawValue, forKey: Self.debugModeKey)
            }
        }
    }
    private static let debugModeKey = "attune.debug.subscriptionMode"
    #endif

    private let storeClient: SubscriptionStoreClient
    private let persistsDebugModeChanges: Bool
    private var transactionListener: Task<Void, Never>?

    init(
        storeClient: SubscriptionStoreClient? = nil,
        listenForTransactions: Bool = true,
        automaticallyRefresh: Bool = true,
        persistsDebugModeChanges: Bool = true
    ) {
        self.storeClient = storeClient ?? LiveSubscriptionStoreClient()
        self.persistsDebugModeChanges = persistsDebugModeChanges
        #if DEBUG
        let savedMode = UserDefaults.standard.string(forKey: Self.debugModeKey)
            .flatMap(DebugSubscriptionMode.init(rawValue:))
        debugMode = savedMode ?? .pro
        #endif

        if listenForTransactions {
            transactionListener = Task { [weak self] in
                for await update in Transaction.updates {
                    guard let self else { return }
                    if case .verified(let transaction) = update {
                        await transaction.finish()
                        await self.refreshEntitlement()
                    }
                }
            }
        }

        if automaticallyRefresh {
            Task { await refresh() }
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    var isBusy: Bool {
        actionState == .purchasing || actionState == .restoring
    }

    var isProductAvailable: Bool { productDetails != nil }

    var hasPremiumAccess: Bool {
        #if DEBUG
        switch debugMode {
        case .pro: return true
        case .free: return false
        case .system: return isSubscribed
        }
        #else
        return isSubscribed
        #endif
    }

    var accessPolicy: SubscriptionAccessPolicy {
        SubscriptionAccessPolicy(hasProAccess: hasPremiumAccess)
    }

    func refresh() async {
        guard !isLoadingProduct else { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        actionState = .idle
        await loadProduct()
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        isSubscribed = await storeClient.hasCurrentMonthlyEntitlement()
    }

    func purchase() async {
        guard !isBusy else { return }
        guard isProductAvailable else {
            actionState = .failed("Attune Pro isn’t available right now. Check your connection and try again.")
            await loadProduct()
            return
        }

        actionState = .purchasing
        do {
            switch try await storeClient.purchaseMonthlyProduct() {
            case .purchased:
                await refreshEntitlement()
                actionState = isSubscribed
                    ? .purchased
                    : .failed("The purchase completed, but Pro access could not be verified yet. Try Restore Purchases.")
            case .pending:
                actionState = .pending
            case .cancelled:
                actionState = .cancelled
            }
        } catch {
            actionState = .failed("The purchase couldn’t be completed. Please try again.")
            AppLogger.log(AppLogger.ERR, "StoreKit purchase failed: \(error.localizedDescription)")
        }
    }

    func restore() async {
        guard !isBusy else { return }
        actionState = .restoring
        do {
            try await storeClient.restorePurchases()
            await refreshEntitlement()
            actionState = isSubscribed ? .restored : .noActiveSubscription
        } catch {
            actionState = .failed("Purchases couldn’t be restored right now. Please try again.")
            AppLogger.log(AppLogger.ERR, "StoreKit restore failed: \(error.localizedDescription)")
        }
    }

    func canStartCheckIn(todayCheckInCount: Int) -> Bool {
        accessPolicy.canStartCheckIn(todayCheckInCount: todayCheckInCount)
    }

    var canUseAllDayRecording: Bool { accessPolicy.canUseListeningSessions }
    var canUseVoiceIntentions: Bool { accessPolicy.canUseVoiceIntentions }

    func canAddIntention(currentCount: Int) -> Bool {
        accessPolicy.canAddIntention(currentCount: currentCount)
    }

    func canSaveIntentions(baselineIDs: Set<String>, proposedIDs: [String]) -> Bool {
        accessPolicy.canSaveIntentions(baselineIDs: baselineIDs, proposedIDs: proposedIDs)
    }

    var canUseInsights: Bool { accessPolicy.canUseInsights }
    var canUseMomentumHistory: Bool { accessPolicy.canUseMomentumHistory }
    var canExportData: Bool { accessPolicy.canExportData }

    var priceText: String {
        if let productDetails {
            return productDetails.displayPrice + " / month"
        }
        return SubscriptionConfig.displayPriceFallback
    }

    private func loadProduct() async {
        do {
            productDetails = try await storeClient.loadMonthlyProduct()
            if productDetails == nil {
                actionState = .failed("Attune Pro is temporarily unavailable. Please try again later.")
            }
        } catch {
            productDetails = nil
            actionState = .failed("Attune Pro couldn’t be loaded. Check your connection and try again.")
            AppLogger.log(AppLogger.ERR, "StoreKit product load failed: \(error.localizedDescription)")
        }
    }
}

enum SubscriptionError: LocalizedError {
    case productUnavailable
    case unverified
    case unknownPurchaseResult

    var errorDescription: String? {
        switch self {
        case .productUnavailable: return "Attune Pro is unavailable."
        case .unverified: return "Could not verify the App Store purchase."
        case .unknownPurchaseResult: return "StoreKit returned an unknown purchase result."
        }
    }
}
