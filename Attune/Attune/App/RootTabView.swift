//
//  RootTabView.swift
//  Attune
//
//  Bottom tab bar with Home, All Day, Library, Settings, and Progress tabs.
//  Uses AppRouter so Home momentum card can switch to Library → Momentum tab.
//

import SwiftUI

struct RootTabView: View {
    @EnvironmentObject var appRouter: AppRouter

    // Track whether recovery has been performed to avoid running it multiple times
    @State private var hasPerformedRecovery = false

    init() {
        // Wire up dependency: inject TranscriptionQueue into RecorderService
        RecorderService.shared.transcriptionQueue = TranscriptionQueue.shared
    }

    var body: some View {
        TabView(selection: $appRouter.selectedRootTab) {
            // Tab 1: Home — daily intentions, momentum card taps to Library → Momentum
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(RootTab.home)
            
            // Tab 2: All Day — continuous recording screen
            HomeRecordView()
                .tabItem {
                    Label("All Day", systemImage: "record.circle")
                }
                .tag(RootTab.allDay)
            
            // Tab 3: Library — browse sessions, segments, insights, momentum
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical.fill")
                }
                .tag(RootTab.library)
            
            // Tab 4: Settings — app settings and logs
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(RootTab.settings)
            
            // Tab 5: Momentum — charted daily progress now lives here
            NavigationStack { // Provide navigation container for Momentum when used as root tab
                MomentumView(selectedDate: appRouter.momentumSelectedDate ?? Date()) // Show Momentum screen and seed date from router when available
            }
                .tabItem {
                    Label("Momentum", systemImage: "chart.line.uptrend.xyaxis") // Rename tab to Momentum while reusing chart icon
                }
                .tag(RootTab.progress) // Keep enum tag unchanged to avoid churn elsewhere
        }
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
