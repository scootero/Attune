//
//  SessionDetailView.swift
//  Pondera
//
//  Consumer listening-session detail. Raw segment state and technical errors
//  remain in diagnostics rather than interrupting this screen.
//

import SwiftUI

struct SessionDetailView: View {
    let sessionId: String

    @State private var session: Session?
    @State private var captures: [ExtractedItem] = []
    @State private var corrections: [String: ItemCorrection] = [:]
    @State private var recap: SessionRecap?

    var body: some View {
        ZStack {
            AttuneScreenBackground()

            if let session {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        sessionHeader(session)

                        if SessionRecapFeature.isEnabled, let recap {
                            SessionRecapView(recap: recap)
                        }

                        if !visibleCaptures.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Captured")
                                    .font(.headline)
                                    .foregroundStyle(AttuneTheme.textPrimary)
                                ForEach(visibleCaptures) { item in
                                    NavigationLink(destination: InsightDetailView(item: item)) {
                                        InsightCaptureRow(item: item, correction: corrections[item.id])
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if let transcript = transcriptText(for: session) {
                            transcriptCard(transcript)
                        } else if visibleCaptures.isEmpty {
                            quietEmptyState
                        }
                    }
                    .padding(.horizontal, AttuneTheme.horizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
            } else {
                ContentUnavailableView(
                    "Session not found",
                    systemImage: "waveform.slash",
                    description: Text("This session is no longer available.")
                )
            }
        }
        .navigationTitle("Talk it out")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadData)
    }

    private func sessionHeader(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Talk it out", systemImage: "waveform")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AttuneTheme.accent)

            Text(session.startedAt.formatted(date: .complete, time: .shortened))
                .font(.title3.weight(.semibold))
                .foregroundStyle(AttuneTheme.textPrimary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    sessionMetadata(session)
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 8) {
                    sessionMetadata(session)
                }
            }
            .font(.caption)
            .foregroundStyle(AttuneTheme.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .attuneCard()
    }

    @ViewBuilder
    private func sessionMetadata(_ session: Session) -> some View {
        if let duration = session.durationFormatted {
            Label(duration, systemImage: "clock")
        }
        Label("\(visibleCaptures.count) captured", systemImage: "sparkles")
    }

    private func transcriptCard(_ transcript: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript")
                .font(.headline)
                .foregroundStyle(AttuneTheme.textPrimary)
            Text(transcript)
                .font(.body)
                .foregroundStyle(AttuneTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .attuneCard()
    }

    private var quietEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundStyle(AttuneTheme.textTertiary)
            Text("Nothing was captured from this session.")
                .font(.subheadline)
                .foregroundStyle(AttuneTheme.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .attuneCard()
    }

    private var visibleCaptures: [ExtractedItem] {
        captures.filter { !($0.applyingCorrection(corrections[$0.id]).isMarkedIncorrect) }
    }

    private func transcriptText(for session: Session) -> String? {
        let stored = session.finalTranscriptText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stored.isEmpty { return stored }

        let joined = session.segments
            .sorted { $0.index < $1.index }
            .compactMap { $0.transcriptText?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    private func loadData() {
        session = SessionStore.shared.loadSession(id: sessionId)
        captures = ExtractionStore.shared.loadExtractions(sessionId: sessionId)
            .sorted { $0.createdAt > $1.createdAt }
        corrections = CorrectionsStore.shared.loadCorrections()

        guard SessionRecapFeature.isEnabled, let session else {
            recap = nil
            return
        }

        recap = SessionRecapBuilder.makeRecap(
            currentSession: session,
            currentItems: captures,
            allSessions: SessionStore.shared.loadAllSessions(),
            allItems: ExtractionStore.shared.loadAllExtractions(),
            topics: SessionRecapTopicSnapshotReader.load(),
            corrections: corrections
        )
    }
}

#Preview {
    NavigationStack { SessionDetailView(sessionId: "sample") }
}
