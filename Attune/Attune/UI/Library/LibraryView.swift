//
//  LibraryView.swift
//  Attune
//
//  Debug cockpit: toggle between Sessions, Segments, and Insights views.
//  Sessions tab has sub-picker: All-day (sessions) | Check-ins.
//

import SwiftUI

/// Sub-tab for Sessions: All-day recordings vs Check-ins
private enum SessionsSubTab {
    case allDay
    case checkIns
}

struct LibraryView: View {
    @EnvironmentObject var appRouter: AppRouter
    
    /// When Sessions is selected: All-day or Check-ins sub-tab
    @State private var sessionsSubTab: SessionsSubTab = .allDay
    
    /// Loaded sessions from disk (for All-day list)
    @State private var sessions: [Session] = []
    
    /// Loaded check-ins from disk (for Check-ins list)
    @State private var checkIns: [CheckIn] = []
    
    var body: some View {
        NavigationStack {  // Use NavigationStack so ProgressContentView's navigationDestination works (NavigationView does not support it)
            VStack(spacing: 0) {
                // Top-level segmented picker (Sessions, Segments, Insights, Momentum)
                Picker("View", selection: $appRouter.selectedLibraryTab) {
                    Text("Sessions").tag(LibraryTab.sessions)
                    Text("Segments").tag(LibraryTab.segments)
                    Text("Insights").tag(LibraryTab.insights)
                    Text("Progress").tag(LibraryTab.momentum) // Rename tab label to Progress while keeping enum for minimal churn
                }
                .pickerStyle(.segmented)
                .padding()
                
                // When Sessions tab: show All-day | Check-ins sub-picker
                if appRouter.selectedLibraryTab == .sessions {
                    Picker("Sessions content", selection: $sessionsSubTab) {
                        Text("All-day").tag(SessionsSubTab.allDay)
                        Text("Check-ins").tag(SessionsSubTab.checkIns)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                
                // Content based on selected tab
                contentView
            }
            .navigationTitle(appRouter.selectedLibraryTab == .momentum ? "Progress" : "Library") // Show Progress title when the repurposed tab is selected
            .onAppear {
                loadData()
            }
            .refreshable {
                loadData()
            }
        }
    }
    
    /// Content for current tab selection
    @ViewBuilder
    private var contentView: some View {
        switch appRouter.selectedLibraryTab {
        case .sessions:
            sessionsContentView
        case .segments:
            if sessions.isEmpty {
                libraryEmptyState(message: "Start a recording to create your first session")
            } else {
                SegmentListView()
            }
        case .insights:
            InsightsListView()
        case .momentum:
            ProgressContentView() // Show Progress content inside Library for the renamed tab
        }
    }
    
    /// Sessions tab content: All-day list or Check-ins list
    @ViewBuilder
    private var sessionsContentView: some View {
        switch sessionsSubTab {
        case .allDay:
            if sessions.isEmpty {
                libraryEmptyState(message: "Start a recording to create your first session")
            } else {
                SessionListView(sessions: sessions)
            }
        case .checkIns:
            CheckInsListView(checkIns: checkIns, title: "Check-ins")
        }
    }
    
    /// Shared empty state for Library (sessions/segments)
    private func libraryEmptyState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("No Data Yet")
                .font(.title2)
                .fontWeight(.semibold)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    /// Loads sessions and check-ins from disk
    private func loadData() {
        sessions = SessionStore.shared.loadAllSessions()
        checkIns = CheckInStore.shared.loadAllCheckIns()
    }
}

/// Represents the tabs in Library view
enum LibraryTab {
    case sessions
    case segments
    case insights
    case momentum
}

#Preview {
    LibraryView()
        .environmentObject(AppRouter())
}
