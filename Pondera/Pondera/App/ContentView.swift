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
    /// Requests iOS voice permissions only after the disclosure has fully dismissed.
    @State private var enableVoiceAfterPrivacyDisclosure = false

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
                OnboardingView(includesNotificationPermissionStep: true) {
                    PonderaOnboardingState.hasCompleted = true
                    PonderaHaptics.saved()
                    showOnboarding = false
                }
                .interactiveDismissDisabled(true)
            }
            .sheet(isPresented: $showAIPrivacySheet, onDismiss: requestVoicePermissionsAfterDisclosureIfNeeded) {
                AIPrivacyDisclosureSheet(
                    onEnableVoice: {
                        completePrivacyDisclosure(enableVoice: true)
                    },
                    onSetUpLater: {
                        completePrivacyDisclosure(enableVoice: false)
                    }
                )
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
        PonderaHaptics.welcome()
        showLaunchIntro = false

        if !PonderaOnboardingState.hasCompleted {
            showOnboarding = true
        } else if !AIPrivacyConsent.hasAccepted {
            showAIPrivacySheet = true
        }
    }

    private func presentPrivacyDisclosureIfNeeded() {
        showAIPrivacySheet = !AIPrivacyConsent.hasAccepted
    }

    private func completePrivacyDisclosure(enableVoice: Bool) {
        // Persist acknowledgement so OpenAIClient may send transcripts.
        AIPrivacyConsent.hasAccepted = true
        enableVoiceAfterPrivacyDisclosure = enableVoice
        PonderaHaptics.saved()
        showAIPrivacySheet = false
    }

    private func requestVoicePermissionsAfterDisclosureIfNeeded() {
        guard enableVoiceAfterPrivacyDisclosure else { return }
        enableVoiceAfterPrivacyDisclosure = false

        Task {
            _ = await PermissionsHelper.requestRecordingPermissions()
        }
    }
}

#Preview {
    ContentView()
}
