//
//  SessionListView.swift
//  Attune
//
//  List of all sessions sorted by startedAt (newest first).
//

import SwiftUI

struct SessionListView: View {
    /// Sessions to display (passed from parent)
    let sessions: [Session]
    
    var body: some View {
        List(sessions) { session in
            NavigationLink(destination: SessionDetailView(sessionId: session.id)) {
                VStack(alignment: .leading, spacing: 6) {
                    // Session ID and status
                    HStack {
                        Text("Session \(session.shortId)")
                            .font(.headline)
                        
                        Spacer()
                        
                        StatusBadge(status: session.status)
                    }
                    
                    // Started time
                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Duration and segment count
                    HStack(spacing: 12) {
                        if let duration = session.durationFormatted {
                            Label(duration, systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Label("\(session.segments.count) segments", systemImage: "waveform")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

/// Status badge view
/// FIX 2: Updated to properly map segment/session status to colors
struct StatusBadge: View {
    let status: String
    
    var body: some View {
        Text(displayText)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(4)
    }
    
    /// Display text for the badge (maps internal status to user-friendly text)
    private var displayText: String {
        switch status {
        case "writing":
            return "writing"
        case "queued":
            return "queued"
        case "transcribing":
            return "processing"
        case "done":
            return "done"
        case "failed":
            return "failed"
        default:
            return status
        }
    }
    
    /// Color based on status
    /// FIX 2: Only show red "failed" badge if status is actually "failed"
    /// Show green "done" badge for status="done" (even if reason=no_speech)
    private var backgroundColor: Color {
        switch status {
        case "recording":
            return .red
        case "stopping":
            return .orange
        case "writing":
            return .orange
        case "queued":
            return .blue
        case "transcribing":
            return .blue
        case "processing":
            return .blue
        case "done":
            return .green // FIX 2: Always green for "done" status
        case "complete":
            return .green
        case "failed":
            return .red // FIX 2: Only red for actual "failed" status
        case "error":
            return .red
        default:
            return .gray
        }
    }
}

#Preview {
    NavigationView {
        SessionListView(sessions: [
            Session(
                id: "abc123",
                startedAt: Date().addingTimeInterval(-3600),
                endedAt: Date(),
                status: "complete",
                segments: [
                    Segment(sessionId: "abc123", index: 0, audioFileName: "seg_0.m4a"),
                    Segment(sessionId: "abc123", index: 1, audioFileName: "seg_1.m4a")
                ]
            )
        ])
    }
}
