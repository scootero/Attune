//
//  AIPrivacyConsent.swift
//  Attune
//
//  Remembers whether the user accepted the AI & privacy disclosure.
//  OpenAI calls are blocked until this is true.
//

import Foundation

/// Stores first-launch acceptance of AI processing (Apple Speech + OpenAI via Attune proxy).
enum AIPrivacyConsent {
    /// UserDefaults key for whether the user accepted the AI disclosure.
    private static let acceptedKey = "attune.aiPrivacy.accepted"

    /// True after the user taps Accept on the disclosure sheet.
    static var hasAccepted: Bool {
        get { UserDefaults.standard.bool(forKey: acceptedKey) }
        set { UserDefaults.standard.set(newValue, forKey: acceptedKey) }
    }
}
