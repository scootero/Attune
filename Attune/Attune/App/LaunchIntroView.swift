//
//  LaunchIntroView.swift
//  Attune
//
//  Plays the short Pondera intro immediately after the static iOS launch screen.
//

import SwiftUI

struct LaunchIntroView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let onFinished: () -> Void

    @State private var introTask: Task<Void, Never>?
    @State private var hasFinished = false
    @State private var isVisible = false

    var body: some View {
        ZStack {
            AttuneScreenBackground()

            VStack(spacing: 18) {
                PonderaBrandMark()
                    .frame(width: 58, height: 58)

                Text("Pondera")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AttuneTheme.textPrimary, AttuneTheme.accent.opacity(0.94)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.96)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: startIntro)
        .onDisappear {
            introTask?.cancel()
        }
    }

    private func startIntro() {
        guard introTask == nil else { return }

        if accessibilityReduceMotion {
            isVisible = true
            introTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                finish()
            }
            return
        }

        withAnimation(.easeOut(duration: 0.35)) {
            isVisible = true
        }

        introTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.05))
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.25)) {
                isVisible = false
            }

            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        introTask?.cancel()
        onFinished()
    }
}
