//
//  OnboardingView.swift
//  Attune
//
//  Benefit-led first-run introduction shown before the required AI/privacy disclosure.
//

import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "waveform.and.mic",
            eyebrow: "VOICE CHECK-INS",
            title: "Speak it. See it move.",
            detail: "An intention is a measurable daily or weekly focus you choose. Tell Attune what you completed and by how much, and a Voice Check-In updates its progress and can capture an optional mood."
        ),
        OnboardingPage(
            icon: "sparkles",
            eyebrow: "TALK IT OUT",
            title: "Notice what keeps coming up.",
            detail: "Talk through what’s on your mind. As themes repeat, Attune may turn one into a small, editable next step chosen to be realistic—not merely repeat what you said. Nothing is added unless you choose it."
        ),
        OnboardingPage(
            icon: "chart.line.uptrend.xyaxis",
            eyebrow: "MOMENTUM",
            title: "Stay focused and in control.",
            detail: "See today's progress and use a free daily reminder. Attune Pro adds history, Week and Month views, Insights, and portable data export."
        )
    ]

    var body: some View {
        ZStack {
            AttuneScreenBackground()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Attune")
                            .font(.title2.bold())
                            .foregroundStyle(AttuneTheme.textPrimary)
                        Spacer()
                        Text("\(selectedPage + 1) of \(pages.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AttuneTheme.textTertiary)
                    }
                    if selectedPage == 0 {
                        Text("Your voice, made meaningful.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AttuneTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)

                TabView(selection: $selectedPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        onboardingPage(page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == selectedPage ? AttuneTheme.accent : AttuneTheme.textTertiary.opacity(0.45))
                            .frame(width: index == selectedPage ? 24 : 8, height: 8)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: selectedPage)
                    }
                }
                .accessibilityHidden(true)
                .padding(.bottom, 22)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: advance) {
                Text(selectedPage == pages.count - 1 ? "Continue" : "Next")
            }
            .buttonStyle(AttunePrimaryButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .accessibilityHint(selectedPage == pages.count - 1 ? "Continues to voice and privacy information" : "Shows the next introduction page")
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if IntentionSuggestionFeature.isEnabled {
                try? IntentionSuggestionStore.shared.bootstrapNewInstall()
            }
        }
    }

    private func onboardingPage(_ page: OnboardingPage) -> some View {
        ScrollView {
            VStack(spacing: 26) {
                ZStack {
                    Circle()
                        .fill(AttuneTheme.accent.opacity(0.14))
                        .frame(width: 132, height: 132)
                    Circle()
                        .stroke(AttuneTheme.accent.opacity(0.28), lineWidth: 1)
                        .frame(width: 132, height: 132)
                    Image(systemName: page.icon)
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(AttuneTheme.accent)
                }
                .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text(page.eyebrow)
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(AttuneTheme.accent)
                    Text(page.title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(AttuneTheme.textPrimary)
                    Text(page.detail)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(AttuneTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(page.eyebrow). \(page.title). \(page.detail)")
    }

    private func advance() {
        if selectedPage < pages.count - 1 {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                selectedPage += 1
            }
        } else {
            onComplete()
        }
    }
}

private struct OnboardingPage {
    let icon: String
    let eyebrow: String
    let title: String
    let detail: String
}

/// Separate from AIPrivacyConsent so the benefit introduction and processing
/// consent remain two explicit, independently auditable first-run steps.
enum AttuneOnboardingState {
    private static let completedKey = "attune.onboarding.completed.v1"

    static var hasCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: completedKey) }
        set { UserDefaults.standard.set(newValue, forKey: completedKey) }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
