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
    /// Acknowledges the disclosure before iOS presents its permission requests.
    var onContinue: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                PonderaScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        disclosureCard
                        actionArea
                    }
                    .padding(.horizontal, PonderaTheme.horizontalPadding)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("VOICE & PRIVACY", systemImage: "hand.raised.fill")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(PonderaTheme.accent)

            Text("How Pondera uses your voice")
                .font(.title2.bold())
                .foregroundStyle(PonderaTheme.textPrimary)

            Text("Review how voice features work before continuing.")
                .font(.subheadline)
                .foregroundStyle(PonderaTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var disclosureCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            disclosurePoint(
                icon: "mic.fill",
                title: "Recording is user-started",
                detail: "Pondera records your voice when you choose to check in or use Talk it out."
            )

            Divider().overlay(PonderaTheme.border)

            disclosurePoint(
                icon: "text.bubble.fill",
                title: "Speech becomes text",
                detail: "Speech recognition may use Apple’s cloud services to turn audio into text."
            )

            Divider().overlay(PonderaTheme.border)

            disclosurePoint(
                icon: "sparkles",
                title: "Text is organized for Pondera",
                detail: "To organize insights and update intentions, Pondera sends transcripts to OpenAI through Pondera’s secure server."
            )

            Text("Privacy Policy, Terms, and Support links stay available in Settings.")
                .font(.caption)
                .foregroundStyle(PonderaTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .ponderaCard()
    }

    private func disclosurePoint(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(PonderaTheme.accent)
                .frame(width: 34, height: 34)
                .background(PonderaTheme.accent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PonderaTheme.textPrimary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(PonderaTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var actionArea: some View {
        VStack(spacing: 12) {
            Text("Pondera uses the microphone to record the voice check-ins you start and Speech Recognition to turn them into text. After you continue, iOS will ask for access to each permission.")
                .font(.footnote)
                .foregroundStyle(PonderaTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Continue", action: onContinue)
                .buttonStyle(PonderaPrimaryButtonStyle())
        }
    }
}
