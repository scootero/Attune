//
//  RootTabView.swift
//  Attune
//
//  Bottom tab bar with Home, All Day, Library, Settings, and Progress tabs.
//  Wires shared instances (RecorderService + TranscriptionQueue).
//

import SwiftUI

struct RootTabView: View {
    
    // Track whether recovery has been performed to avoid running it multiple times
    @State private var hasPerformedRecovery = false
    
    init() {
        // Wire up dependency: inject TranscriptionQueue into RecorderService
        // This allows RecorderService to enqueue segments when they're closed
        RecorderService.shared.transcriptionQueue = TranscriptionQueue.shared
    }
    
    var body: some View {
        TabView {
            // Tab 1: Home — stub for future daily intentions
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            
            // Tab 2: All Day — continuous recording screen (renamed from Record; UI only)
            HomeRecordView()
                .tabItem {
                    Label("All Day", systemImage: "record.circle")
                }
            
            // Tab 3: Library — browse sessions and segments
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical.fill")
                }
            
            // Tab 4: Settings — app settings and logs
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
            
            // Tab 5: Progress — stub for future goals/tracking
            ProgressView()
                .tabItem {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                }
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
}
