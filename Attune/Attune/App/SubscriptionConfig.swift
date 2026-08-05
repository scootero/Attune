//
//  SubscriptionConfig.swift
//  Attune
//
//  Fixed product IDs and free-tier limits for Attune Pro.
//

import Foundation

/// Subscription product IDs and simple free vs paid rules.
enum SubscriptionConfig {
    /// Must match App Store Connect Product ID exactly.
    static let monthlyProductID = "com.scottoliver.Attune.monthly"

    /// Free users can start this many check-ins per calendar day.
    static let freeCheckInsPerDay = 1

    /// Free users may create one active tracked intention. Existing Pro data is
    /// never deleted when an entitlement expires; this only gates adding more.
    static let freeActiveIntentionsLimit = 1

    /// Product-wide safety cap used by both Free and Pro intention editors.
    static let maximumActiveIntentions = 10

    /// Consumer-facing plan name. The underlying App Store product remains monthly.
    static let displayName = "Attune Pro"

    /// Short marketing line for the paywall.
    static let displayPriceFallback = "$4.99/month"

    /// App Store Connect must contain the matching introductory offer before release.
    static let trialDurationText = "3-day free trial"
}
