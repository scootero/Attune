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
    @State private var showSettings = false
    @State private var reminderConfirmation: String?

    init() {
        // Wire up dependency: inject TranscriptionQueue into RecorderService
        RecorderService.shared.transcriptionQueue = TranscriptionQueue.shared
        AttuneTheme.configureAppearance()
    }

    var body: some View {
        VStack(spacing: 0) {
            appHeader
                .zIndex(1)

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
                            title: "Talk it out",
                            detail: "Talk through what’s on your mind. Pondera organizes clear intentions, commitments, events, and states into reviewable Insights.",
                            icon: "waveform.badge.mic"
                        )
                    }
                }
                    .tabItem {
                        Label("Talk", systemImage: "waveform.circle.fill")
                            .accessibilityLabel("Talk it out")
                    }
                    .tag(RootTab.allDay)

                // Tab 3: Insights — captures, recurring themes, and history.
                Group {
                    if subscriptionManager.canUseInsights {
                        LibraryView()
                    } else {
                        ProLockedFeatureView(
                            title: "Insights",
                            detail: "Review what Pondera found when you talked things out and notice themes that repeat over time.",
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
        }
        .tint(AttuneTheme.accent)
        .preferredColorScheme(.dark)
        .background(AttuneScreenBackground())
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(subscriptionManager)
        }
        .alert("Okay", isPresented: Binding(
            get: { reminderConfirmation != nil },
            set: { if !$0 { reminderConfirmation = nil } }
        )) {
            Button("Got it", role: .cancel) { reminderConfirmation = nil }
        } message: {
            Text(reminderConfirmation ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .attuneDailyReminderRouteRequested)) { _ in
            handlePendingReminderRoute()
        }
        .onChange(of: appRouter.selectedRootTab) { _, selectedTab in
            guard selectedTab == .home else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                IntentionSuggestionToastCenter.shared.presentPendingHomeSuggestion()
            }
        }
        .onAppear {
            // Perform recovery on first appearance only
            if !hasPerformedRecovery {
                performRecoveryOnLaunch()
                hasPerformedRecovery = true
            }
            handlePendingReminderRoute()
        }
    }

    private func handlePendingReminderRoute() {
        guard let route = DailyReminderNotificationService.shared.consumePendingRoute() else { return }
        appRouter.navigateToProgressUpdate(intentionID: route.intentionId)
        if route.showsFollowUpConfirmation {
            reminderConfirmation = "We’ll check back in one hour if you haven’t updated your progress."
        }
    }

    private var appHeader: some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            Spacer(minLength: 0)

            HStack(spacing: 9) {
                PonderaBrandMark()
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)

                Text("Pondera")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                AttuneTheme.textPrimary,
                                Color.white.opacity(0.88),
                                AttuneTheme.accent.opacity(0.94)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AttuneTheme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .background(AttuneTheme.surface.opacity(0.72), in: Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.28), AttuneTheme.border],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: AttuneTheme.accent.opacity(0.08), radius: 12, y: 5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .accessibilityHint("Opens Pondera settings")
        }
        .padding(.horizontal, AttuneTheme.horizontalPadding)
        .padding(.vertical, 6)
        .background {
            AttuneHeaderGlassBackground()
                .frame(height: 72)
                .offset(y: 8)
                .ignoresSafeArea(edges: .top)
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

private struct AttuneHeaderGlassBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency {
                AttuneTheme.background.opacity(0.98)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)

                LinearGradient(
                    colors: [
                        AttuneTheme.background.opacity(0.76),
                        AttuneTheme.background.opacity(0.38),
                        AttuneTheme.background.opacity(0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Ellipse()
                    .fill(AttuneTheme.accent.opacity(0.10))
                    .frame(width: 210, height: 48)
                    .blur(radius: 22)
                    .offset(x: -95, y: -14)

                Ellipse()
                    .fill(AttuneTheme.accentSecondary.opacity(0.08))
                    .frame(width: 170, height: 42)
                    .blur(radius: 24)
                    .offset(x: 120, y: -10)
            }
        }
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, Color.white.opacity(reduceTransparency ? 0.05 : 0.14), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 0.5)
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.72),
                    .init(color: .black.opacity(0.82), location: 0.88),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

#Preview {
    RootTabView()
        .environmentObject(AppRouter())
}
