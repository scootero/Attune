//
//  ContentView.swift
//  Pondera
//
//  Created by Scott Oliver on 1/31/26.
//

import SwiftUI

// ContentView creates AppRouter, subscription state, and the AI privacy sheet.
struct ContentView: View {
    @StateObject private var appRouter = AppRouter()
    /// Shared StoreKit subscription state for paywall + feature gates.
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var aiUsageNoticeCenter = AIUsageNoticeCenter.shared
    /// The static iOS launch screen hands off to this short branded animation.
    @State private var showLaunchIntro = true
    /// Benefit-led introduction appears once, before the separate processing disclosure.
    @State private var showOnboarding = false
    /// Drives the first-launch AI disclosure; starts false if consent already saved.
    @State private var showAIPrivacySheet = false

    var body: some View {
        ZStack {
            RootTabView()
                .environmentObject(appRouter)
                .environmentObject(subscriptionManager)

            if showLaunchIntro {
                LaunchIntroView(onFinished: finishLaunchIntro)
                    .zIndex(1)
            }
        }
        .onAppear {
            EngagementMetricsStore.shared.recordAppLaunchOnce()
        }
            .fullScreenCover(isPresented: $showOnboarding, onDismiss: presentPrivacyDisclosureIfNeeded) {
                OnboardingView {
                    AttuneOnboardingState.hasCompleted = true
                    AttuneHaptics.saved()
                    showOnboarding = false
                }
                .interactiveDismissDisabled(true)
            }
            .sheet(isPresented: $showAIPrivacySheet) {
                AIPrivacyDisclosureSheet {
                    // Persist acceptance so OpenAIClient may send transcripts.
                    AIPrivacyConsent.hasAccepted = true
                    AttuneHaptics.saved()
                    showAIPrivacySheet = false
                }
                .interactiveDismissDisabled(true) // Require an explicit Accept tap.
            }
            .alert(item: $aiUsageNoticeCenter.notice) { notice in
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .preferredColorScheme(.dark)
    }

    private func finishLaunchIntro() {
        AttuneHaptics.welcome()
        showLaunchIntro = false

        if !AttuneOnboardingState.hasCompleted {
            showOnboarding = true
        } else if !AIPrivacyConsent.hasAccepted {
            showAIPrivacySheet = true
        }
    }

    private func presentPrivacyDisclosureIfNeeded() {
        showAIPrivacySheet = !AIPrivacyConsent.hasAccepted
    }
}

#Preview {
    ContentView()
}
