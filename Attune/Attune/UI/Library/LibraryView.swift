//
//  LibraryView.swift
//  Attune
//
//  Consumer Insights home: recent captures, themes, and recording history.
//  The former segment/debug cockpit is intentionally not part of this surface.
//

import SwiftUI

struct LibraryView: View {
    @State private var items: [ExtractedItem] = []
    @State private var topics: [TopicAggregate] = []
    @State private var corrections: [String: ItemCorrection] = [:]
    @State private var sessions: [Session] = []
    @State private var checkIns: [CheckIn] = []

    var body: some View {
        NavigationStack {
            ZStack {
                AttuneScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        if visibleItems.isEmpty && visibleTopics.isEmpty {
                            emptyState
                        } else {
                            summaryCard
                            themesSection
                            recentSection
                        }

                        historySection
                    }
                    .padding(.horizontal, AttuneTheme.horizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 104)
                }
                .scrollIndicators(.hidden)
                .refreshable { loadData() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: loadData)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Insights")
                .font(.title.bold())
                .foregroundStyle(AttuneTheme.textPrimary)
            Text("What you’ve said—and what keeps coming up.")
                .font(.subheadline)
                .foregroundStyle(AttuneTheme.textSecondary)
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 0) {
            summaryMetric(value: visibleItems.count, label: "Captured", icon: "sparkles")
            Rectangle()
                .fill(AttuneTheme.border)
                .frame(width: 1, height: 40)
            summaryMetric(value: recurringTopicCount, label: "Recurring", icon: "repeat")
            Rectangle()
                .fill(AttuneTheme.border)
                .frame(width: 1, height: 40)
            summaryMetric(value: sessions.count, label: "Sessions", icon: "waveform")
        }
        .padding(.vertical, 14)
        .attuneCard()
    }

    private func summaryMetric(value: Int, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(AttuneTheme.accent)
                    .accessibilityHidden(true)
                Text("\(value)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(AttuneTheme.textPrimary)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(AttuneTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }

    private var themesSection: some View {
        Group {
            if !featuredTopics.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(
                        title: recurringTopicCount > 0 ? "Recurring themes" : "Themes forming",
                        subtitle: recurringTopicCount > 0 ? "Ideas you’ve returned to." : "Related ideas Attune has started grouping.",
                        destination: InsightsListView(initialTab: .themes)
                    )

                    ForEach(featuredTopics) { summary in
                        NavigationLink(destination: TopicDetailView(topic: summary.topic)) {
                            TopicSummaryRow(summary: summary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var recentSection: some View {
        Group {
            if !visibleItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(
                        title: "Recent captures",
                        subtitle: "Organized from your Listening Sessions.",
                        destination: InsightsListView(initialTab: .captures)
                    )

                    ForEach(Array(visibleItems.prefix(2))) { item in
                        NavigationLink(destination: InsightDetailView(item: item)) {
                            InsightCaptureRow(item: item, correction: corrections[item.id])
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func sectionHeader<Destination: View>(title: String, subtitle: String, destination: Destination) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AttuneTheme.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AttuneTheme.textSecondary)
            }
            Spacer()
            NavigationLink(destination: destination) {
                Text("View all")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AttuneTheme.accent)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History")
                .font(.headline)
                .foregroundStyle(AttuneTheme.textPrimary)

            VStack(spacing: 0) {
                NavigationLink(destination: SessionListView(sessions: sessions)) {
                    historyRow(
                        title: "Listening sessions",
                        detail: "\(sessions.count) saved",
                        icon: "waveform"
                    )
                }
                .buttonStyle(.plain)

                Divider().overlay(AttuneTheme.border)

                NavigationLink(destination: CheckInsListView(checkIns: checkIns, title: "Voice Check-Ins")) {
                    historyRow(
                        title: "Voice check-ins",
                        detail: "\(checkIns.count) saved",
                        icon: "mic"
                    )
                }
                .buttonStyle(.plain)
            }
            .attuneCard()
        }
    }

    private func historyRow(title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(AttuneTheme.accent)
                .frame(width: 34, height: 34)
                .background(AttuneTheme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AttuneTheme.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AttuneTheme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AttuneTheme.textTertiary)
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(AttuneTheme.accent)
            Text("Your patterns will appear here")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AttuneTheme.textPrimary)
            Text("Start a Listening Session and speak naturally. Attune will organize clear intentions, commitments, events, and states—and group related ideas over time.")
                .font(.subheadline)
                .foregroundStyle(AttuneTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .attuneCard()
    }

    private var visibleItems: [ExtractedItem] {
        items.filter { !($0.applyingCorrection(corrections[$0.id]).isMarkedIncorrect) }
    }

    private var visibleTopics: [ConsumerTopicSummary] {
        topics.compactMap { topic in
            let occurrences = ItemResolver.resolveItems(itemIds: topic.itemIds)
                .filter { !($0.applyingCorrection(corrections[$0.id]).isMarkedIncorrect) }
                .sorted { $0.createdAt > $1.createdAt }
            guard !occurrences.isEmpty else { return nil }
            return ConsumerTopicSummary(topic: topic, occurrences: occurrences)
        }
        .sorted { lhs, rhs in
            if lhs.mentionCount != rhs.mentionCount { return lhs.mentionCount > rhs.mentionCount }
            return lhs.topic.lastSeenAtISO > rhs.topic.lastSeenAtISO
        }
    }

    private var recurringTopicCount: Int {
        visibleTopics.filter { $0.mentionCount > 1 }.count
    }

    private var featuredTopics: [ConsumerTopicSummary] {
        let recurring = visibleTopics.filter { $0.mentionCount > 1 }
        return recurring.isEmpty ? Array(visibleTopics.prefix(2)) : Array(recurring.prefix(2))
    }

    private func loadData() {
        corrections = CorrectionsStore.shared.loadCorrections()
        items = ExtractionStore.shared.loadAllExtractions()
        topics = Array(TopicAggregateStore.shared.loadTopics().values)
        sessions = SessionStore.shared.loadAllSessions().sorted { $0.startedAt > $1.startedAt }
        checkIns = CheckInStore.shared.loadAllCheckIns().sorted { $0.createdAt > $1.createdAt }
    }
}

// Kept for AppRouter source compatibility. The consumer Insights UI no longer
// exposes these former debug-cockpit tabs.
enum LibraryTab {
    case sessions
    case segments
    case insights
    case momentum
}

#Preview {
    LibraryView()
}
