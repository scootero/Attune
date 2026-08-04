//
//  SubscriptionConfig.swift
//  Attune
//
//  Fixed product IDs and free-tier limits for the $5.99/month plan.
//

import Foundation

/// Subscription product IDs and simple free vs paid rules.
enum SubscriptionConfig {
    /// Must match App Store Connect Product ID exactly.
    static let monthlyProductID = "com.scottoliver.Attune.monthly"

    /// Free users can start this many check-ins per calendar day.
    static let freeCheckInsPerDay = 3

    /// Display name shown on the paywall.
    static let displayName = "Attune Monthly"

    /// Short marketing line for the paywall.
    static let displayPriceFallback = "$5.99/month"
}
