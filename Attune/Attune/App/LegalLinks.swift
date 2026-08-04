//
//  LegalLinks.swift
//  Attune
//
//  Public URLs for Privacy Policy, Terms, and Support.
//  Replace placeholders after you host the real pages (Phase 5).
//

import Foundation

/// Central place for App Store / About legal and support URLs.
enum LegalLinks {
    /// Privacy Policy page (required for App Store Connect when processing personal data).
    static let privacyPolicy = URL(string: "https://example.com/attune/privacy")!

    /// Terms of Use page (your app terms).
    static let termsOfUse = URL(string: "https://example.com/attune/terms")!

    /// Apple’s standard Licensed Application End User License Agreement (accepted for subscriptions).
    static let appleStandardEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// Support / contact page or mailto landing page.
    static let support = URL(string: "https://example.com/attune/support")!
}
