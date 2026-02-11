//
//  SegmentListView.swift
//  Attune
//
//  Flattened list of all segments across all sessions.
//

import SwiftUI

struct SegmentListView: View {
    /// All segments loaded from disk (flattened across sessions)
    @State private var segmentPairs: [(session: Session, segment: Segment)] = []
    
    var body: some View {
        List {
            ForEach(segmentPairs, id: \.segment.id) { pair in
                NavigationLink(destination: SegmentDetailView(sessionId: pair.session.id, segmentId: pair.segment.id)) {
                    VStack(alignment: .leading, spacing: 6) {
                        // Segment header: session shortId + segment index
                        HStack {
                            Text("Session \(pair.session.shortId) • Seg \(pair.segment.index)")
                                .font(.headline)
                            
                            Spacer()
                            
                            StatusBadge(status: pair.segment.status)
                        }
                        
                        // Started time
                        Text(pair.segment.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // Transcript status
                        HStack(spacing: 12) {
                            if pair.segment.transcriptText != nil && !pair.segment.transcriptText!.isEmpty {
                                Label("Has transcript", systemImage: "text.quote")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Label("No transcript", systemImage: "text.quote")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            // Show error indicator if present
                            if pair.segment.error != nil {
                                Label("Error", systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .onAppear {
            loadSegments()
        }
        .refreshable {
            loadSegments()
        }
    }
    
    /// Loads and sorts all segments
    private func loadSegments() {
        let allSegments = SessionStore.shared.loadAllSegments()
        
        // Sort by segment startedAt descending (most recent first)
        segmentPairs = allSegments.sorted { $0.segment.startedAt > $1.segment.startedAt }
    }
}

#Preview {
    NavigationView {
        SegmentListView()
    }
}
