//
//  SubscriptionConfig.swift
//  Pondera
//
//  Fixed product IDs and free-tier limits for Pondera Pro.
//

import Foundation

/// Subscription product IDs and simple free vs paid rules.
enum SubscriptionConfig {
    /// Must match App Store Connect Product ID exactly.
    static let monthlyProductID = "com.scottoliver.Pondera.Intentions.monthly"

    /// Code-distributed, non-consumable entitlement for permanent Pro access.
    /// This product is intentionally not presented as a public purchase option.
    static let lifetimeProductID = "com.scottoliver.Pondera.Intentions.lifetime"

    /// Any current entitlement in this set unlocks the same Pondera Pro features.
    static let proProductIDs: Set<String> = [monthlyProductID, lifetimeProductID]

    /// Free users can start this many check-ins per calendar day.
    static let freeCheckInsPerDay = 1

    /// Free users can complete one Talk it out session per calendar day.
    static let freeListeningSessionsPerDay = 1

    /// Free users may create one active tracked intention. Existing Pro data is
    /// never deleted when an entitlement expires; this only gates adding more.
    static let freeActiveIntentionsLimit = 1

    /// Product-wide safety cap used by both Free and Pro intention editors.
    static let maximumActiveIntentions = 10

    /// Consumer-facing plan name. The public App Store product remains monthly.
    static let displayName = "Pondera Pro"

    /// Short marketing line for the paywall.
    static let displayPriceFallback = "$3.99/month"

}
