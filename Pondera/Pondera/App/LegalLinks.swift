//
//  LegalLinks.swift
//  Pondera
//
//  Public GitHub Pages URLs for Privacy Policy, Terms, and Support.
//

import Foundation

/// Central place for App Store / About legal and support URLs.
enum LegalLinks {
    /// Privacy Policy page (required for App Store Connect when processing personal data).
    static let privacyPolicy = URL(string: "https://scootero.github.io/Attune/privacy/")!

    /// Terms of Use page (your app terms).
    static let termsOfUse = URL(string: "https://scootero.github.io/Attune/terms/")!

    /// Apple’s standard Licensed Application End User License Agreement (accepted for subscriptions).
    static let appleStandardEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// Support / contact page or mailto landing page.
    static let support = URL(string: "https://scootero.github.io/Attune/support/")!
}
