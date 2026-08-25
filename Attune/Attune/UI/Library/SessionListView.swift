//
//  SessionListView.swift
//  Attune
//
//  Consumer listening-session history. Segment counts, IDs, and terminal
//  transcription failures are intentionally omitted from this list.
//

import SwiftUI

struct SessionListView: View {
    let sessions: [Session]

    var body: some View {
        Group {
            if sessions.isEmpty {
                insightsEmptyState(
                    icon: "waveform",
                    title: "No past sessions yet",
                    detail: "Open Talk when you want to think out loud and let Pondera organize what you say."
                )
            } else {
                List(sessions.sorted { $0.startedAt > $1.startedAt }) { session in
                    NavigationLink(destination: SessionDetailView(sessionId: session.id)) {
                        sessionRow(session)
                    }
                    .listRowBackground(AttuneTheme.backgroundRaised)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(AttuneScreenBackground())
        .navigationTitle("Past sessions")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sessionRow(_ session: Session) -> some View {
        let capturedCount = ExtractionStore.shared.loadExtractions(sessionId: session.id).count

        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AttuneTheme.textPrimary)
                Spacer()
                if let state = activeState(session.status) {
                    Text(state)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AttuneTheme.accent)
                }
            }

            HStack(spacing: 12) {
                if let duration = session.durationFormatted {
                    Label(duration, systemImage: "clock")
                }
                Label("\(capturedCount) captured", systemImage: "sparkles")
            }
            .font(.caption)
            .foregroundStyle(AttuneTheme.textSecondary)
        }
        .padding(.vertical, 5)
    }

    private func activeState(_ status: String) -> String? {
        switch status {
        case "recording": return "Talking"
        case "stopping", "processing": return "Organizing"
        default: return nil
        }
    }
}

// Retained for developer-only segment views that are not reachable from the
// consumer Insights navigation.
struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(status.capitalized)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.18), in: Capsule())
            .foregroundStyle(Color.secondary)
    }
}

#Preview {
    NavigationStack { SessionListView(sessions: []) }
}
