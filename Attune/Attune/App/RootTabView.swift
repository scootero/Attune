//
//  RootTabView.swift
//  Attune
//
//  Bottom tab bar with Home, Library, and Settings tabs.
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
            // Home tab: Record screen
            HomeRecordView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            
            // Library tab: Browse sessions and segments
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical.fill")
                }
            
            // Settings tab: App settings and logs
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
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
