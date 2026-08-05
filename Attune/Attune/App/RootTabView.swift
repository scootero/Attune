//
//  RootTabView.swift
//  Attune
//
//  Four consumer-facing tabs: Today, Record, Insights, and Momentum.
//  Uses AppRouter so Home momentum card can switch to Library → Momentum tab.
//

import SwiftUI

struct RootTabView: View {
    @EnvironmentObject var appRouter: AppRouter
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    // Track whether recovery has been performed to avoid running it multiple times
    @State private var hasPerformedRecovery = false

    init() {
        // Wire up dependency: inject TranscriptionQueue into RecorderService
        RecorderService.shared.transcriptionQueue = TranscriptionQueue.shared
        AttuneTheme.configureAppearance()
    }

    var body: some View {
        TabView(selection: $appRouter.selectedRootTab) {
            // Tab 1: Today — check-ins, intentions, mood, and weekly summary.
            HomeView()
                .tabItem {
                    Label("Today", systemImage: "house.fill")
                }
                .tag(RootTab.home)
            
            // Tab 2: Record — user-started Listening Sessions.
            Group {
                if subscriptionManager.canUseAllDayRecording {
                    HomeRecordView()
                } else {
                    ProLockedFeatureView(
                        title: "Listening Sessions",
                        detail: "Start a longer capture when you choose. Attune organizes clear intentions, commitments, events, and states into reviewable Insights.",
                        icon: "waveform.badge.mic"
                    )
                }
            }
                .tabItem {
                    Label("Record", systemImage: "waveform.circle.fill")
                }
                .tag(RootTab.allDay)
            
            // Tab 3: Insights — captures, recurring themes, and history.
            Group {
                if subscriptionManager.canUseInsights {
                    LibraryView()
                } else {
                    ProLockedFeatureView(
                        title: "Insights",
                        detail: "Review what Attune found in your Listening Sessions and notice themes that repeat over time.",
                        icon: "sparkles"
                    )
                }
            }
                .tabItem {
                    Label("Insights", systemImage: "sparkles")
                }
                .tag(RootTab.library)
            
            // Tab 5: Momentum — charted daily progress now lives here
            NavigationStack { // Provide navigation container for Momentum when used as root tab
                if subscriptionManager.canUseMomentumHistory {
                    MomentumView(selectedDate: appRouter.momentumSelectedDate ?? Date()) // Full historical Momentum for Pro
                } else {
                    FreeMomentumTodayView() // Free is intentionally limited to the current day
                }
            }
                .tabItem {
                    Label("Momentum", systemImage: "chart.line.uptrend.xyaxis") // Rename tab to Momentum while reusing chart icon
                }
                .tag(RootTab.progress) // Keep enum tag unchanged to avoid churn elsewhere
        }
        .tint(AttuneTheme.accent)
        .preferredColorScheme(.dark)
        .onAppear {
            // Perform recovery on first appearance only
            if !hasPerformedRecovery {
                performRecoveryOnLaunch()
                hasPerformedRecovery = true
            }
        }
    }
    
    /// Performs recovery of incomplete sessions and segments on app launch.
    /// This ensures that if the app was terminated or suspended mid-recording or mid-transcription,
    /// the work is properly reconciled and transcription resumes without data loss.
    @MainActor
    private func performRecoveryOnLaunch() {
        print("[RootTabView] Performing recovery on app launch")
        
        // Step 1: Recover incomplete sessions (fix status inconsistencies)
        // This will:
        // - Mark sessions that were "recording" as "error"
        // - Reset segments that were "transcribing" back to "queued"
        let _ = SessionStore.shared.recoverIncompleteSessionsOnLaunch()
        
        // Step 2: Enqueue all eligible segments for transcription
        // This will scan all sessions and enqueue segments that are:
        // - "queued" (pending transcription)
        // - "failed" with audio file still present (retry eligible)
        TranscriptionQueue.shared.enqueueAllEligibleSegmentsOnLaunch()
        
        print("[RootTabView] Recovery complete")
    }
}

#Preview {
    RootTabView()
        .environmentObject(AppRouter())
}
