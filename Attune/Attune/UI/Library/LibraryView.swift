//
//  LibraryView.swift
//  Attune
//
//  Debug cockpit: toggle between Sessions and Segments views.
//

import SwiftUI

struct LibraryView: View {
    /// Selected tab: Sessions or Segments
    @State private var selectedTab: LibraryTab = .sessions
    
    /// Loaded sessions from disk (shared state for both views)
    @State private var sessions: [Session] = []
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Segmented picker at top
                Picker("View", selection: $selectedTab) {
                    Text("Sessions").tag(LibraryTab.sessions)
                    Text("Segments").tag(LibraryTab.segments)
                    Text("Insights").tag(LibraryTab.insights)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content based on selected tab
                if sessions.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "tray")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)
                        
                        Text("No Data Yet")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Start a recording to create your first session")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Show appropriate list based on selection
                    if selectedTab == .sessions {
                        SessionListView(sessions: sessions)
                    } else if selectedTab == .segments {
                        SegmentListView()
                    } else {
                        InsightsListView()
                    }
                }
            }
            .navigationTitle("Library")
            .onAppear {
                loadSessions()
            }
            .refreshable {
                loadSessions()
            }
        }
    }
    
    /// Loads all sessions from disk
    private func loadSessions() {
        sessions = SessionStore.shared.loadAllSessions()
    }
}

/// Represents the three tabs in Library view
enum LibraryTab {
    case sessions
    case segments
    case insights
}

#Preview {
    LibraryView()
}
