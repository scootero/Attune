//
//  AIPrivacyDisclosureSheet.swift
//  Attune
//
//  First-launch sheet explaining mic, speech recognition, and AI processing.
//  User must accept before Attune sends transcripts to the AI proxy.
//

import SwiftUI

/// Simple disclosure UI shown until AIPrivacyConsent.hasAccepted is true.
struct AIPrivacyDisclosureSheet: View {
    /// Called when the user accepts so the parent can dismiss and persist consent.
    var onAccept: () -> Void

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text("How Pondera uses your voice")
                    .font(.title2.bold())

                Text("Pondera records your voice when you choose to check in or use Talk it out. Speech recognition may use Apple’s cloud services to turn audio into text.")
                    .font(.body)
                    .foregroundColor(.secondary)

                Text("To organize insights and update intentions, Pondera sends those transcripts to OpenAI through Pondera’s secure server. Your voice and text are used only for this purpose inside the app.")
                    .font(.body)
                    .foregroundColor(.secondary)

                Text("You can review Privacy Policy, Terms, and Support links anytime in Settings → About.")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: onAccept) {
                    Text("I Understand")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
