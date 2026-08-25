//
//  InsightsListView.swift
//  Attune
//
//  Consumer views for the items and recurring topics produced by listening
//  sessions. Internal extraction scores, fingerprints, IDs, and segments stay
//  out of the primary UI.
//

import SwiftUI

enum InsightsTab: String, CaseIterable {
    case captures = "Captured"
    case themes = "Themes"
}

struct ConsumerTopicSummary: Identifiable {
    let topic: TopicAggregate
    let occurrences: [ExtractedItem]

    var id: String { topic.id }
    var mentionCount: Int { occurrences.count }
}

struct InsightsListView: View {
    @State private var selectedTab: InsightsTab
    @State private var items: [ExtractedItem] = []
    @State private var topics: [TopicAggregate] = []
    @State private var corrections: [String: ItemCorrection] = [:]
    @State private var searchText = ""
    @State private var selectedType = "all"

    init(initialTab: InsightsTab = .captures) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Insights view", selection: $selectedTab) {
                ForEach(InsightsTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AttuneTheme.horizontalPadding)
            .padding(.vertical, 12)

            if selectedTab == .captures {
                typeFilters
                capturesContent
            } else {
                themesContent
            }
        }
        .background(AttuneScreenBackground())
        .navigationTitle(selectedTab.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: selectedTab == .captures ? "Search captures" : "Search themes")
        .onAppear(perform: loadData)
        .refreshable { loadData() }
    }

    private var typeFilters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                filterChip(title: "All", value: "all")
                filterChip(title: "Intentions", value: ExtractedItem.ItemType.intention)
                filterChip(title: "Commitments", value: ExtractedItem.ItemType.commitment)
                filterChip(title: "Events", value: ExtractedItem.ItemType.event)
                filterChip(title: "States", value: ExtractedItem.ItemType.state)
            }
            .padding(.horizontal, AttuneTheme.horizontalPadding)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func filterChip(title: String, value: String) -> some View {
        Button {
            selectedType = value
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selectedType == value ? AttuneTheme.background : AttuneTheme.textSecondary)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(selectedType == value ? AttuneTheme.accent : AttuneTheme.surfaceStrong, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedType == value ? .isSelected : [])
    }

    private var capturesContent: some View {
        Group {
            if filteredItems.isEmpty {
                insightsEmptyState(
                    icon: searchText.isEmpty && selectedType == "all" ? "waveform.badge.mic" : "magnifyingglass",
                    title: searchText.isEmpty && selectedType == "all" ? "Nothing captured yet" : "No matching captures",
                    detail: searchText.isEmpty && selectedType == "all"
                        ? "Use Talk it out and speak naturally. Clear intentions, commitments, events, and states will appear here."
                        : "Try another search or filter."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredItems) { item in
                            NavigationLink(destination: InsightDetailView(item: item)) {
                                InsightCaptureRow(item: item, correction: corrections[item.id])
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AttuneTheme.horizontalPadding)
                    .padding(.vertical, 8)
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var themesContent: some View {
        Group {
            if filteredTopics.isEmpty {
                insightsEmptyState(
                    icon: searchText.isEmpty ? "repeat" : "magnifyingglass",
                    title: searchText.isEmpty ? "No themes yet" : "No matching themes",
                    detail: searchText.isEmpty
                        ? "Themes form as Pondera groups related ideas when you talk things out. Repeated ideas will show a higher mention count."
                        : "Try another search."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredTopics) { summary in
                            NavigationLink(destination: TopicDetailView(topic: summary.topic)) {
                                TopicSummaryRow(summary: summary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AttuneTheme.horizontalPadding)
                    .padding(.vertical, 8)
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var filteredItems: [ExtractedItem] {
        visibleItems.filter { item in
            let corrected = item.applyingCorrection(corrections[item.id])
            let matchesType = selectedType == "all" || corrected.displayType == selectedType
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || corrected.displayTitle.localizedCaseInsensitiveContains(query)
                || item.summary.localizedCaseInsensitiveContains(query)
                || corrected.displayCategories.contains { InsightDisplay.categoryLabel($0).localizedCaseInsensitiveContains(query) }
            return matchesType && matchesSearch
        }
    }

    private var visibleItems: [ExtractedItem] {
        items.filter { !($0.applyingCorrection(corrections[$0.id]).isMarkedIncorrect) }
    }

    private var filteredTopics: [ConsumerTopicSummary] {
        visibleTopics.filter { summary in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return query.isEmpty
                || summary.topic.displayTitle.localizedCaseInsensitiveContains(query)
                || summary.topic.categories.contains { InsightDisplay.categoryLabel($0).localizedCaseInsensitiveContains(query) }
        }
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

    private func loadData() {
        items = ExtractionStore.shared.loadAllExtractions()
        topics = Array(TopicAggregateStore.shared.loadTopics().values)
        corrections = CorrectionsStore.shared.loadCorrections()
    }
}

struct InsightCaptureRow: View {
    let item: ExtractedItem
    let correction: ItemCorrection?
    var isNewlySeen = false

    private var corrected: CorrectedItemView { item.applyingCorrection(correction) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                TypeBadge(type: corrected.displayType)
                Spacer()
                Text(InsightDisplay.relativeDate(item.createdAt))
                    .font(.caption)
                    .foregroundStyle(AttuneTheme.textTertiary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AttuneTheme.textTertiary)
            }

            Text(corrected.displayTitle)
                .font(.headline)
                .foregroundStyle(AttuneTheme.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            if !item.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(item.summary)
                    .font(.subheadline)
                    .foregroundStyle(AttuneTheme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }

            if let category = corrected.displayCategories.first {
                Label(InsightDisplay.categoryLabel(category), systemImage: InsightDisplay.categoryIcon(category))
                    .font(.caption)
                    .foregroundStyle(AttuneTheme.textTertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .insightCaptureCard(isHighlighted: isNewlySeen)
    }
}

struct TopicSummaryRow: View {
    let summary: ConsumerTopicSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: summary.mentionCount > 1 ? "repeat" : "circle.dotted")
                    .foregroundStyle(AttuneTheme.accentSecondary)
                Text(summary.mentionCount > 1 ? "Recurring theme" : "Mentioned once")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AttuneTheme.accentSecondary)
                Spacer()
                Text("\(summary.mentionCount) \(summary.mentionCount == 1 ? "mention" : "mentions")")
                    .font(.caption)
                    .foregroundStyle(AttuneTheme.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AttuneTheme.textTertiary)
            }

            Text(summary.topic.displayTitle)
                .font(.headline)
                .foregroundStyle(AttuneTheme.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            HStack {
                if let category = summary.topic.categories.first {
                    Text(InsightDisplay.categoryLabel(category))
                }
                Spacer()
                Text("Last mentioned \(InsightDisplay.relativeDate(summary.topic.lastSeenAtISO))")
            }
            .font(.caption)
            .foregroundStyle(AttuneTheme.textTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .attuneCard()
    }
}

struct TypeBadge: View {
    let type: String

    var body: some View {
        Label(InsightDisplay.typeLabel(type), systemImage: InsightDisplay.typeIcon(type))
            .font(.caption.weight(.semibold))
            .foregroundStyle(InsightDisplay.typeColor(type))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(InsightDisplay.typeColor(type).opacity(0.13), in: Capsule())
    }
}

@ViewBuilder
func insightsEmptyState(icon: String, title: String, detail: String) -> some View {
    VStack(spacing: 12) {
        Image(systemName: icon)
            .font(.system(size: 34, weight: .medium))
            .foregroundStyle(AttuneTheme.accent)
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(AttuneTheme.textPrimary)
        Text(detail)
            .font(.subheadline)
            .foregroundStyle(AttuneTheme.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
    .padding(22)
    .frame(maxWidth: .infinity)
    .attuneCard()
    .padding(.horizontal, AttuneTheme.horizontalPadding)
    .padding(.top, 24)
}

enum InsightDisplay {
    static func typeLabel(_ type: String) -> String {
        switch type {
        case ExtractedItem.ItemType.event: return "Event"
        case ExtractedItem.ItemType.intention: return "Intention"
        case ExtractedItem.ItemType.commitment: return "Commitment"
        case ExtractedItem.ItemType.state: return "State"
        default: return "Capture"
        }
    }

    static func typeIcon(_ type: String) -> String {
        switch type {
        case ExtractedItem.ItemType.event: return "calendar"
        case ExtractedItem.ItemType.intention: return "scope"
        case ExtractedItem.ItemType.commitment: return "checkmark.circle"
        case ExtractedItem.ItemType.state: return "heart.text.square"
        default: return "sparkles"
        }
    }

    static func typeColor(_ type: String) -> Color {
        switch type {
        case ExtractedItem.ItemType.event: return AttuneTheme.accentSecondary
        case ExtractedItem.ItemType.intention: return AttuneTheme.accent
        case ExtractedItem.ItemType.commitment: return AttuneTheme.warning
        case ExtractedItem.ItemType.state: return AttuneTheme.success
        default: return AttuneTheme.textSecondary
        }
    }

    static func categoryLabel(_ category: String) -> String {
        category.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func categoryIcon(_ category: String) -> String {
        switch category {
        case ExtractedItem.Category.fitnessHealth: return "figure.run"
        case ExtractedItem.Category.careerWork: return "briefcase"
        case ExtractedItem.Category.moneyFinance: return "dollarsign.circle"
        case ExtractedItem.Category.personalGrowth: return "leaf"
        case ExtractedItem.Category.relationshipsSocial: return "person.2"
        case ExtractedItem.Category.stressLoad: return "waveform.path.ecg"
        case ExtractedItem.Category.peaceWellbeing: return "sun.max"
        default: return "tag"
        }
    }

    static func date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    static func relativeDate(_ value: String) -> String {
        guard let date = date(value) else { return "Recently" }
        if abs(date.timeIntervalSinceNow) < 60 || date > Date() { return "Just now" }
        return date.formatted(.relative(presentation: .named))
    }

    static func fullDate(_ value: String) -> String {
        guard let date = date(value) else { return "Recently" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

#Preview {
    NavigationStack {
        InsightsListView()
    }
}
