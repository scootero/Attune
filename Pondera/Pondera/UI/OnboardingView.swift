//
//  OnboardingView.swift
//  Pondera
//
//  Benefit-led first-run introduction shown before the required AI/privacy disclosure.
//

import Foundation
import SwiftUI

struct OnboardingView: View {
    let finalButtonTitle: String
    let onComplete: () -> Void
    let includesNotificationPermissionStep: Bool

    init(finalButtonTitle: String = "Continue", includesNotificationPermissionStep: Bool = false, onComplete: @escaping () -> Void) {
        self.finalButtonTitle = finalButtonTitle
        self.includesNotificationPermissionStep = includesNotificationPermissionStep
        self.onComplete = onComplete
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPage = 0
    @State private var hasRevealed = false

    private var pages: [OnboardingPage] {
        var pages = [
        OnboardingPage(
            illustration: .intro,
            accent: PonderaTheme.accent,
            eyebrow: "PONDERA",
            title: "Turn your voice into visible intentions.",
            detail: "Choose what matters, say what happened, and let Pondera keep the next step clear enough to act on."
        ),
        OnboardingPage(
            illustration: .voice,
            accent: PonderaTheme.recording,
            eyebrow: "VOICE CHECK-INS",
            title: "Speak it. See it move.",
            detail: "Tell Pondera what you completed and by how much. A Voice Check-In updates the intentions you chose and can capture an optional mood."
        ),
        OnboardingPage(
            illustration: .insight,
            accent: PonderaTheme.accentSecondary,
            eyebrow: "TALK IT OUT",
            title: "Notice what keeps coming up.",
            detail: "Talk through what’s on your mind. As themes repeat, Pondera may turn one into a small, editable next step chosen to be realistic—not merely repeat what you said. Nothing is added unless you choose it."
        ),
        OnboardingPage(
            illustration: .momentum,
            accent: PonderaTheme.accent,
            eyebrow: "MOMENTUM",
            title: "Stay focused and in control.",
            detail: "See today's progress and use a free daily reminder. Pondera Pro adds history, Week and Month views, Insights, and portable data export."
        )
        ]
        if includesNotificationPermissionStep {
            pages.append(OnboardingPage(
                illustration: .notifications,
                accent: PonderaTheme.accentSecondary,
                eyebrow: "DAILY REMINDERS",
                title: "A gentle nudge, on your terms.",
                detail: "Pondera can remind you at your chosen time when you have not updated your progress. You can change the time or turn reminders off in Settings."
            ))
        }
        return pages
    }

    var body: some View {
        ZStack {
            PonderaScreenBackground()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        PonderaWordmark(size: .onboarding, alignment: .leading)
                        Spacer()
                        Text("\(selectedPage + 1) of \(pages.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(PonderaTheme.textTertiary)
                            .padding(.leading, 12)
                    }
                    if selectedPage == 0 {
                        Text("Your voice, made meaningful.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(PonderaTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)

                TabView(selection: pageSelection) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        onboardingPage(page, isActive: index == selectedPage)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == selectedPage ? PonderaTheme.accent : PonderaTheme.textTertiary.opacity(0.45))
                            .frame(width: index == selectedPage ? 24 : 8, height: 8)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: selectedPage)
                    }
                }
                .accessibilityHidden(true)
                .padding(.bottom, 22)
            }

            Color.black
                .ignoresSafeArea()
                .opacity(hasRevealed ? 0 : 1)
                .allowsHitTesting(false)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: advance) {
                Text(selectedPage == pages.count - 1 ? finalButtonTitle : "Next")
            }
            .buttonStyle(PonderaPrimaryButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .accessibilityHint(selectedPage == pages.count - 1 ? finalButtonAccessibilityHint : "Shows the next introduction page")
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if IntentionSuggestionFeature.isEnabled {
                try? IntentionSuggestionStore.shared.bootstrapNewInstall()
            }

            revealOnboarding()
        }
    }

    private func onboardingPage(_ page: OnboardingPage, isActive: Bool) -> some View {
        ScrollView {
            VStack(spacing: 26) {
                OnboardingIllustration(page: page, isActive: isActive)
                    .frame(width: 176, height: 176)
                .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text(page.eyebrow)
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(page.accent)
                    Text(page.title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(PonderaTheme.textPrimary)
                    Text(page.detail)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(PonderaTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)

                if page.illustration == .notifications {
                    VStack(spacing: 10) {
                        Button { requestNotifications() } label: {
                            Label(isRequestingNotifications ? "Asking…" : "Enable Notifications", systemImage: "bell.badge.fill")
                        }
                        .buttonStyle(PonderaPrimaryButtonStyle())
                        .disabled(isRequestingNotifications)

                        Text("Not now is always okay. You can enable them later in Settings.")
                            .font(.footnote)
                            .foregroundStyle(PonderaTheme.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: page.illustration == .notifications ? .contain : .combine)
        .accessibilityLabel("\(page.eyebrow). \(page.title). \(page.detail)")
    }

    @State private var isRequestingNotifications = false

    private func requestNotifications() {
        isRequestingNotifications = true
        Task {
            _ = await PermissionsHelper.requestNotificationPermissions()
            await MainActor.run { isRequestingNotifications = false }
        }
    }

    private func revealOnboarding() {
        guard !hasRevealed else { return }

        if reduceMotion {
            hasRevealed = true
        } else {
            withAnimation(.easeOut(duration: 0.48)) {
                hasRevealed = true
            }
        }
    }

    private func advance() {
        if selectedPage < pages.count - 1 {
            PonderaHaptics.selection()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                selectedPage += 1
            }
        } else {
            onComplete()
        }
    }

    private var finalButtonAccessibilityHint: String {
        finalButtonTitle == "Done"
            ? "Closes the Pondera walkthrough"
            : "Continues to voice and privacy information"
    }

    /// Adds the same light feedback when onboarding pages change by swiping.
    private var pageSelection: Binding<Int> {
        Binding(
            get: { selectedPage },
            set: { page in
                guard page != selectedPage else { return }
                PonderaHaptics.selection()
                selectedPage = page
            }
        )
    }
}

private struct OnboardingPage {
    let illustration: OnboardingIllustration.Kind
    let accent: Color
    let eyebrow: String
    let title: String
    let detail: String
}

private struct OnboardingIllustration: View {
    enum Kind {
        case intro
        case voice
        case insight
        case momentum
        case notifications
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let page: OnboardingPage
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = reduceMotion || !isActive ? 0 : context.date.timeIntervalSinceReferenceDate

            ZStack {
                Circle()
                    .fill(page.accent.opacity(0.12))
                    .frame(width: 156, height: 156)
                Circle()
                    .stroke(page.accent.opacity(0.24), lineWidth: 1)
                    .frame(width: 156, height: 156)
                Circle()
                    .stroke(page.accent.opacity(0.08), lineWidth: 18)
                    .frame(width: 118, height: 118)
                    .scaleEffect(1 + pulse(phase, speed: 0.7, amount: 0.035))

                illustrationContent(phase: phase)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(isActive && !reduceMotion ? 1 : 0.98)
            .opacity(isActive ? 1 : 0.86)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: isActive)
        }
    }

    @ViewBuilder
    private func illustrationContent(phase: TimeInterval) -> some View {
        switch page.illustration {
        case .intro:
            introIllustration(phase: phase)
        case .voice:
            voiceIllustration(phase: phase)
        case .insight:
            insightIllustration(phase: phase)
        case .momentum:
            momentumIllustration(phase: phase)
        case .notifications:
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(page.accent)
                .symbolEffect(.pulse, options: .repeating, isActive: isActive && !reduceMotion)
        }
    }

    private func introIllustration(phase: TimeInterval) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index == 1 ? PonderaTheme.accentSecondary : page.accent)
                    .frame(width: 8 + CGFloat(index * 3), height: 8 + CGFloat(index * 3))
                    .offset(
                        x: cosValue(phase, offset: Double(index) * 2.1, radius: 56),
                        y: sinValue(phase, offset: Double(index) * 2.1, radius: 38)
                    )
                    .opacity(0.46)
            }

            PonderaBrandMark()
                .frame(width: 56, height: 56)
                .shadow(color: page.accent.opacity(0.38), radius: 16)

            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(page.accent)
                .offset(x: -44, y: -36)
                .opacity(0.85 + pulse(phase, speed: 1.6, amount: 0.15))

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(PonderaTheme.success)
                .offset(x: 45, y: 38)
                .scaleEffect(1 + pulse(phase, speed: 0.9, amount: 0.06))
        }
    }

    private func voiceIllustration(phase: TimeInterval) -> some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { index in
                    Capsule()
                        .fill(page.accent.opacity(0.78))
                        .frame(width: 5, height: voiceBarHeight(index: index, phase: phase))
                }
            }
            .offset(y: 42)

            Image(systemName: "mic.fill")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(page.accent)
                .offset(y: -12)

            Circle()
                .stroke(page.accent.opacity(0.20), lineWidth: 2)
                .frame(width: 78, height: 78)
                .scaleEffect(1 + pulse(phase, speed: 1.2, amount: 0.08))
        }
    }

    private func insightIllustration(phase: TimeInterval) -> some View {
        ZStack {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(PonderaTheme.textPrimary.opacity(0.17))
                        .frame(width: 72 - CGFloat(index * 14), height: 7)
                        .offset(x: sinValue(phase, offset: Double(index), radius: 3))
                }
            }
            .offset(x: -24, y: 24)

            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(page.accent)
                .offset(x: 20, y: -18)
                .scaleEffect(1 + pulse(phase, speed: 0.95, amount: 0.08))

            Image(systemName: "arrow.up.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(PonderaTheme.background)
                .frame(width: 34, height: 28)
                .background(PonderaTheme.accent, in: Capsule())
                .offset(x: 26, y: 42)
        }
    }

    private func momentumIllustration(phase: TimeInterval) -> some View {
        ZStack(alignment: .bottomLeading) {
            Path { path in
                path.move(to: CGPoint(x: 22, y: 112))
                path.addLine(to: CGPoint(x: 54, y: 86))
                path.addLine(to: CGPoint(x: 82, y: 96))
                path.addLine(to: CGPoint(x: 122, y: 44))
            }
            .trim(from: 0, to: 0.82 + pulse(phase, speed: 0.55, amount: 0.18))
            .stroke(page.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            .frame(width: 144, height: 132)

            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(index == 3 ? page.accent : PonderaTheme.textPrimary.opacity(0.20))
                    .frame(width: 15, height: 26 + CGFloat(index * 15))
                    .offset(x: 24 + CGFloat(index * 28), y: -14)
                    .scaleEffect(y: 0.86 + pulse(phase + Double(index) * 0.35, speed: 0.7, amount: 0.14), anchor: .bottom)
            }
        }
        .frame(width: 144, height: 132)
    }

    private func voiceBarHeight(index: Int, phase: TimeInterval) -> CGFloat {
        18 + CGFloat(index % 4) * 6 + pulse(phase + Double(index) * 0.5, speed: 2.2, amount: 10)
    }

    private func pulse(_ phase: TimeInterval, speed: Double, amount: CGFloat) -> CGFloat {
        (CGFloat(sin(phase * speed)) + 1) * amount
    }

    private func sinValue(_ phase: TimeInterval, offset: Double, radius: CGFloat) -> CGFloat {
        CGFloat(sin(phase * 0.7 + offset)) * radius
    }

    private func cosValue(_ phase: TimeInterval, offset: Double, radius: CGFloat) -> CGFloat {
        CGFloat(cos(phase * 0.7 + offset)) * radius
    }
}

/// Separate from AIPrivacyConsent so the benefit introduction and processing
/// consent remain two explicit, independently auditable first-run steps.
enum PonderaOnboardingState {
    private static let completedKey = "attune.onboarding.completed.v1"

    static var hasCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: completedKey) }
        set { UserDefaults.standard.set(newValue, forKey: completedKey) }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
