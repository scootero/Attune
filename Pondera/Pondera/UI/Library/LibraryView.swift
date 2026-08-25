//
//  LibraryView.swift
//  Pondera
//
//  Consumer Insights home: recent captures, themes, and recording history.
//  The former segment/debug cockpit is intentionally not part of this surface.
//

import SwiftUI

struct LibraryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var items: [ExtractedItem] = []
    @State private var topics: [TopicAggregate] = []
    @State private var corrections: [String: ItemCorrection] = [:]
    @State private var sessions: [Session] = []
    @State private var checkIns: [CheckIn] = []
    @State private var highlightedCaptureIDs: Set<String> = []
    @State private var unseenCalendarCaptureIDs: Set<String> = []
    @State private var seenFeedbackToken = UUID()

    private let seenStore = InsightSeenStore()

    var body: some View {
        NavigationStack {
            ZStack {
                PonderaScreenBackground()

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

                        if CalendarFeature.isEnabled {
                            calendarSection
                        }

                        historySection
                    }
                    .padding(.horizontal, PonderaTheme.horizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 104)
                }
                .scrollIndicators(.hidden)
                .refreshable { loadData() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: loadData)
            .task(id: seenFeedbackToken) {
                guard !highlightedCaptureIDs.isEmpty || !unseenCalendarCaptureIDs.isEmpty else { return }
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                finishSeenFeedback()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Insights")
                    .font(.title.bold())
                    .foregroundStyle(PonderaTheme.textPrimary)
                Text("What you’ve said—and what keeps coming up.")
                    .font(.subheadline)
                    .foregroundStyle(PonderaTheme.textSecondary)
            }

            Spacer(minLength: 4)

            if CalendarFeature.isEnabled {
                NavigationLink(destination: PonderaCalendarView()) {
                    CalendarShortcutLabel(hasUnseenEvents: !unseenCalendarCaptureIDs.isEmpty)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded(markCalendarCapturesSeen))
                .accessibilityHint("Opens your captured events calendar")
            }
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 0) {
            summaryMetric(value: visibleItems.count, label: "Captured", icon: "sparkles")
            Rectangle()
                .fill(PonderaTheme.border)
                .frame(width: 1, height: 40)
            summaryMetric(value: recurringTopicCount, label: "Recurring", icon: "repeat")
            Rectangle()
                .fill(PonderaTheme.border)
                .frame(width: 1, height: 40)
            summaryMetric(value: sessions.count, label: "Sessions", icon: "waveform")
        }
        .padding(.vertical, 14)
        .ponderaCard()
    }

    private func summaryMetric(value: Int, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(PonderaTheme.accent)
                    .accessibilityHidden(true)
                Text("\(value)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(PonderaTheme.textPrimary)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(PonderaTheme.textSecondary)
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
                        subtitle: recurringTopicCount > 0 ? "Ideas you’ve returned to." : "Related ideas Pondera has started grouping.",
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
                        subtitle: "Organized when you talk things out.",
                        destination: InsightsListView(initialTab: .captures)
                    )

                    ForEach(Array(visibleItems.prefix(2))) { item in
                        NavigationLink(destination: InsightDetailView(item: item)) {
                            InsightCaptureRow(
                                item: item,
                                correction: corrections[item.id],
                                isNewlySeen: highlightedCaptureIDs.contains(item.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 0.65),
                            value: highlightedCaptureIDs.contains(item.id)
                        )
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
                    .foregroundStyle(PonderaTheme.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(PonderaTheme.textSecondary)
            }
            Spacer()
            NavigationLink(destination: destination) {
                Text("View all")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PonderaTheme.accent)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History")
                .font(.headline)
                .foregroundStyle(PonderaTheme.textPrimary)

            VStack(spacing: 0) {
                NavigationLink(destination: SessionListView(sessions: sessions)) {
                    historyRow(
                        title: "Past sessions",
                        detail: "\(sessions.count) saved",
                        icon: "waveform"
                    )
                }
                .buttonStyle(.plain)

                Divider().overlay(PonderaTheme.border)

                NavigationLink(destination: CheckInsListView(checkIns: checkIns, title: "Voice Check-Ins")) {
                    historyRow(
                        title: "Voice check-ins",
                        detail: "\(checkIns.count) saved",
                        icon: "mic"
                    )
                }
                .buttonStyle(.plain)
            }
            .ponderaCard()
        }
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plan from your captures")
                .font(.headline)
                .foregroundStyle(PonderaTheme.textPrimary)

            NavigationLink(destination: PonderaCalendarView()) {
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.headline)
                        .foregroundStyle(PonderaTheme.accent)
                        .frame(width: 38, height: 38)
                        .background(PonderaTheme.accent.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calendar")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PonderaTheme.textPrimary)
                        Text(calendarCaptureCount == 0
                             ? (undatedCalendarEventCount == 0
                                ? "Clear dates and times will appear here."
                                : "\(undatedCalendarEventCount) event\(undatedCalendarEventCount == 1 ? "" : "s") need a date")
                             : "\(calendarCaptureCount) dated capture\(calendarCaptureCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(PonderaTheme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PonderaTheme.textTertiary)
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .ponderaCard()
        }
    }

    private var calendarCaptureCount: Int {
        CalendarCaptureParser.captures(from: items, corrections: corrections).count
    }

    private var undatedCalendarEventCount: Int {
        CalendarCaptureParser.undatedCaptures(from: items, corrections: corrections).count
    }

    private func historyRow(title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(PonderaTheme.accent)
                .frame(width: 34, height: 34)
                .background(PonderaTheme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PonderaTheme.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(PonderaTheme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PonderaTheme.textTertiary)
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(PonderaTheme.accent)
            Text("Your patterns will appear here")
                .font(.title3.weight(.semibold))
                .foregroundStyle(PonderaTheme.textPrimary)
            Text("Use Talk it out and speak naturally. Pondera will organize clear intentions, commitments, events, and states—and group related ideas over time.")
                .font(.subheadline)
                .foregroundStyle(PonderaTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .ponderaCard()
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
        let loadedCorrections = CorrectionsStore.shared.loadCorrections()
        let loadedItems = ExtractionStore.shared.loadAllExtractions()
        let loadedVisibleItems = loadedItems.filter {
            !($0.applyingCorrection(loadedCorrections[$0.id]).isMarkedIncorrect)
        }
        let unseenIDs = seenStore.unseenIDs(in: loadedVisibleItems.map(\.id))

        corrections = loadedCorrections
        items = loadedItems
        topics = Array(TopicAggregateStore.shared.loadTopics().values)
        sessions = SessionStore.shared.loadAllSessions().sorted { $0.startedAt > $1.startedAt }
        checkIns = CheckInStore.shared.loadAllCheckIns().sorted { $0.createdAt > $1.createdAt }
        highlightedCaptureIDs = unseenIDs
        unseenCalendarCaptureIDs = Set(
            loadedVisibleItems
                .filter { $0.applyingCorrection(loadedCorrections[$0.id]).displayType == ExtractedItem.ItemType.event }
                .map(\.id)
        ).intersection(unseenIDs)
        seenFeedbackToken = UUID()
    }

    private func finishSeenFeedback() {
        let IDsToMark = highlightedCaptureIDs.union(unseenCalendarCaptureIDs)
        seenStore.markSeen(IDsToMark, retaining: items.map(\.id))
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.65)) {
            highlightedCaptureIDs.removeAll()
            unseenCalendarCaptureIDs.removeAll()
        }
    }

    private func markCalendarCapturesSeen() {
        let IDsToMark = unseenCalendarCaptureIDs
        seenStore.markSeen(IDsToMark, retaining: items.map(\.id))
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            highlightedCaptureIDs.subtract(IDsToMark)
            unseenCalendarCaptureIDs.removeAll()
        }
    }
}

private struct CalendarShortcutLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let hasUnseenEvents: Bool
    @State private var isPulsing = false

    var body: some View {
        Label("Calendar", systemImage: hasUnseenEvents ? "calendar.badge.exclamationmark" : "calendar")
            .font(.caption.weight(.semibold))
            .foregroundStyle(hasUnseenEvents ? PonderaTheme.textPrimary : PonderaTheme.accent)
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .background(
                hasUnseenEvents ? PonderaTheme.accentSecondary.opacity(0.24) : PonderaTheme.accent.opacity(0.12),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        hasUnseenEvents ? PonderaTheme.accentSecondary.opacity(isPulsing ? 0.95 : 0.42) : PonderaTheme.accent.opacity(0.28),
                        lineWidth: hasUnseenEvents ? (isPulsing ? 2 : 1.25) : 1
                    )
            }
            .shadow(
                color: hasUnseenEvents ? PonderaTheme.accentSecondary.opacity(isPulsing ? 0.38 : 0.16) : .clear,
                radius: isPulsing ? 10 : 5,
                y: 3
            )
            .scaleEffect(hasUnseenEvents && isPulsing && !reduceMotion ? 1.035 : 1)
            .contentShape(Capsule())
            .onAppear(perform: updateAnimation)
            .onChange(of: hasUnseenEvents) { _, _ in updateAnimation() }
            .accessibilityLabel(hasUnseenEvents ? "Calendar, new captured events" : "Calendar")
    }

    private func updateAnimation() {
        guard hasUnseenEvents, !reduceMotion else {
            isPulsing = false
            return
        }
        isPulsing = false
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
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
