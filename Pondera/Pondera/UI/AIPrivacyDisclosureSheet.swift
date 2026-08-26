//
//  AIPrivacyDisclosureSheet.swift
//  Pondera
//
//  First-launch sheet explaining mic, speech recognition, and AI processing.
//  User must accept before Pondera sends transcripts to the AI proxy.
//

import SwiftUI

/// Simple disclosure UI shown until AIPrivacyConsent.hasAccepted is true.
struct AIPrivacyDisclosureSheet: View {
    /// Both actions acknowledge the disclosure. Voice setup remains optional.
    var onEnableVoice: () -> Void
    var onSetUpLater: () -> Void

    var body: some View {
        NavigationView {
            ScrollView {
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

                    Divider()

                    Text("If you enable voice now, iOS will ask for Microphone and Speech Recognition access next.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Button(action: onEnableVoice) {
                        Text("Continue and Enable Voice")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                    Button("Not Now", action: onSetUpLater)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.secondary)

                    Text("You can enable voice later when you start a Voice Check-In or use Talk it out.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
