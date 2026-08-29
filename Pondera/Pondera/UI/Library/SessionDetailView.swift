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
            PonderaScreenBackground()

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
                                    .foregroundStyle(PonderaTheme.textPrimary)
                                ForEach(visibleCaptures) { item in
                                    NavigationLink(destination: InsightDetailView(item: item)) {
                                        InsightCaptureRow(item: item, correction: corrections[item.id])
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if let transcript = transcriptText(for: session) {
                            transcriptCard(transcript, session: session)
                        } else if hasLowTrustTranscript(session) {
                            lowTrustEmptyState(session)
                        } else if visibleCaptures.isEmpty {
                            quietEmptyState
                        }
                    }
                    .padding(.horizontal, PonderaTheme.horizontalPadding)
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
                .foregroundStyle(PonderaTheme.accent)

            Text(session.startedAt.formatted(date: .complete, time: .shortened))
                .font(.title3.weight(.semibold))
                .foregroundStyle(PonderaTheme.textPrimary)

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
            .foregroundStyle(PonderaTheme.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ponderaCard()
    }

    @ViewBuilder
    private func sessionMetadata(_ session: Session) -> some View {
        if let duration = session.durationFormatted {
            Label(duration, systemImage: "clock")
        }
        Label("\(visibleCaptures.count) captured", systemImage: "sparkles")
        let quality = transcriptQualitySummary(for: session)
        Label(quality.label, systemImage: quality.systemImage)
    }

    private func transcriptCard(_ transcript: String, session: Session) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Transcript")
                    .font(.headline)
                    .foregroundStyle(PonderaTheme.textPrimary)
                Spacer(minLength: 8)
                let quality = transcriptQualitySummary(for: session)
                Text(quality.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(quality.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(quality.color.opacity(0.14), in: Capsule())
            }

            if let tokens = redactedTranscriptTokens(for: session) {
                RedactedTranscriptFlow(tokens: tokens)
                Text("Black marks show unclear audio that Pondera skipped.")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(PonderaTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(transcript)
                    .font(.body)
                    .foregroundStyle(PonderaTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(transcriptTrustNote(for: session))
                .font(.caption)
                .italic()
                .foregroundStyle(PonderaTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ponderaCard()
    }

    private var quietEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundStyle(PonderaTheme.textTertiary)
            Text("Nothing was captured from this session.")
                .font(.subheadline)
                .foregroundStyle(PonderaTheme.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .ponderaCard()
    }

    private func lowTrustEmptyState(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Low confidence recording", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("This session was too unclear to trust, so Pondera skipped Insights for it.")
                .font(.subheadline)
                .foregroundStyle(PonderaTheme.textSecondary)
            if let confidence = sessionAverageConfidence(session) {
                Text("Average transcript confidence: \(Int((confidence * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PonderaTheme.textSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ponderaCard()
    }

    private var visibleCaptures: [ExtractedItem] {
        captures.filter { !($0.applyingCorrection(corrections[$0.id]).isMarkedIncorrect) }
    }

    private func transcriptText(for session: Session) -> String? {
        let stored = session.finalTranscriptText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stored.isEmpty { return stored }

        let joined = session.segments
            .sorted { $0.index < $1.index }
            .map { $0.extractionTranscriptText }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    private func redactedTranscriptTokens(for session: Session) -> [TranscriptDisplayToken]? {
        var tokens: [TranscriptDisplayToken] = []
        var trustedWords: [String] = []
        var sawRedaction = false

        func flushTrustedWords() {
            guard !trustedWords.isEmpty else { return }
            tokens.append(TranscriptDisplayToken(text: trustedWords.joined(separator: " "), isRedaction: false))
            trustedWords.removeAll()
        }

        for segment in session.segments.sorted(by: { $0.index < $1.index }) {
            guard let spans = segment.transcriptSpans, !spans.isEmpty else { continue }
            var pendingRedaction = false

            for span in spans {
                let text = span.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }

                if span.trust == "trusted" {
                    if pendingRedaction {
                        flushTrustedWords()
                        tokens.append(TranscriptDisplayToken(text: "...", isRedaction: true))
                        sawRedaction = true
                        pendingRedaction = false
                    }
                    trustedWords.append(text)
                    if trustedWords.count >= 6 {
                        flushTrustedWords()
                    }
                } else {
                    pendingRedaction = true
                }
            }

            if pendingRedaction {
                flushTrustedWords()
                tokens.append(TranscriptDisplayToken(text: "...", isRedaction: true))
                sawRedaction = true
            }
            flushTrustedWords()
        }

        return sawRedaction && tokens.contains(where: { !$0.isRedaction }) ? tokens : nil
    }

    private func transcriptTrustNote(for session: Session) -> String {
        let quality = transcriptQualitySummary(for: session).label
        switch quality {
        case "High confidence":
            return "Pondera uses this transcript to create Insights when the words are clear enough."
        case "Mixed confidence":
            return "Pondera only uses the clearer parts of this transcript for Insights."
        case "Low confidence":
            return "Pondera skipped unclear parts so they do not become Insights."
        case "No clear speech":
            return "Pondera did not find enough clear speech to create Insights."
        default:
            return "Pondera checks transcript confidence before creating Insights."
        }
    }

    private func hasLowTrustTranscript(_ session: Session) -> Bool {
        session.segments.contains { segment in
            let raw = segment.transcriptText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !raw.isEmpty && (segment.transcriptQuality == "lowTrust" || segment.extractionTranscriptText.isEmpty)
        }
    }

    private func sessionAverageConfidence(_ session: Session) -> Double? {
        let values = session.segments.compactMap(\.transcriptConfidence)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func transcriptQualitySummary(for session: Session) -> (label: String, systemImage: String, color: Color) {
        let completed = session.segments.filter { $0.status == "done" }
        let qualities = completed.compactMap(\.transcriptQuality)
        guard !qualities.isEmpty else {
            return ("Quality unknown", "questionmark.circle", PonderaTheme.textSecondary)
        }

        if qualities.allSatisfy({ $0 == "silent" }) {
            return ("No clear speech", "waveform.slash", PonderaTheme.textSecondary)
        }
        if qualities.contains("lowTrust") {
            return ("Low confidence", "exclamationmark.triangle.fill", .orange)
        }
        if qualities.contains("mixed") {
            return ("Mixed confidence", "waveform.badge.exclamationmark", .yellow)
        }
        return ("High confidence", "checkmark.circle.fill", .green)
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

private struct TranscriptDisplayToken: Identifiable {
    let id = UUID()
    let text: String
    let isRedaction: Bool
}

private struct RedactedTranscriptFlow: View {
    let tokens: [TranscriptDisplayToken]

    var body: some View {
        TranscriptFlowLayout(spacing: 6) {
            ForEach(tokens) { token in
                if token.isRedaction {
                    Text(token.text)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.82), in: Capsule())
                        .accessibilityLabel("Unclear audio skipped")
                } else {
                    Text(token.text)
                        .font(.body)
                        .foregroundStyle(PonderaTheme.textSecondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

private struct TranscriptFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += min(size.width, maxWidth) + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let width = min(size.width, bounds.width)
            if x > bounds.minX && x + width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: width, height: size.height)
            )
            x += width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    NavigationStack { SessionDetailView(sessionId: "sample") }
}
