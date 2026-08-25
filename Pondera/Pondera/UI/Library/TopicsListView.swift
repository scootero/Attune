//
//  TopicsListView.swift
//  Pondera
//
//  Consumer list of grouped themes. Counts are derived from visible resolved
//  captures so items marked incorrect do not inflate the UI.
//

import SwiftUI

struct TopicsListView: View {
    @State private var topics: [TopicAggregate] = []
    @State private var corrections: [String: ItemCorrection] = [:]
    @State private var searchText = ""

    var body: some View {
        Group {
            if filteredTopics.isEmpty {
                insightsEmptyState(
                    icon: searchText.isEmpty ? "repeat" : "magnifyingglass",
                    title: searchText.isEmpty ? "No themes yet" : "No matching themes",
                    detail: searchText.isEmpty
                        ? "Related ideas from what you say in Talk it out will be grouped here."
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
                    .padding(.vertical, 12)
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(AttuneScreenBackground())
        .navigationTitle("Themes")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search themes")
        .onAppear(perform: loadData)
        .refreshable { loadData() }
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
        topics = Array(TopicAggregateStore.shared.loadTopics().values)
        corrections = CorrectionsStore.shared.loadCorrections()
    }
}

#Preview {
    NavigationStack { TopicsListView() }
}
