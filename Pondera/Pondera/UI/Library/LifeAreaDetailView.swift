//
//  LifeAreaDetailView.swift
//  Pondera
//

import SwiftUI

struct LifeAreaDetailView: View {
    let category: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var items: [ExtractedItem] = []
    @State private var topics: [TopicAggregate] = []
    @State private var corrections: [String: ItemCorrection] = [:]
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            PonderaScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if !areaTopics.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Themes in this area")
                                .font(.headline)
                                .foregroundStyle(PonderaTheme.textPrimary)
                            ForEach(areaTopics) { summary in
                                NavigationLink(destination: TopicDetailView(topic: summary.topic)) {
                                    TopicSummaryRow(summary: summary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent captures")
                            .font(.headline)
                            .foregroundStyle(PonderaTheme.textPrimary)
                        ForEach(areaItems) { item in
                            NavigationLink(destination: InsightDetailView(item: item)) {
                                InsightCaptureRow(item: item, correction: corrections[item.id])
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, PonderaTheme.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared ? 1 : 0.985)
        }
        .navigationTitle(InsightDisplay.categoryLabel(category))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadData()
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.easeOut(duration: 0.34)) {
                    hasAppeared = true
                }
            }
        }
    }

    private var header: some View {
        let sessions = Set(areaItems.map(\.sessionId)).count
        return VStack(alignment: .leading, spacing: 12) {
            Label(InsightDisplay.categoryLabel(category), systemImage: InsightDisplay.categoryIcon(category))
                .font(.caption.weight(.semibold))
                .foregroundStyle(PonderaTheme.accentSecondary)
            Text("What has been present")
                .font(.title2.bold())
                .foregroundStyle(PonderaTheme.textPrimary)
            Text("\(areaItems.count) \(areaItems.count == 1 ? "capture" : "captures") across \(sessions) \(sessions == 1 ? "session" : "sessions")")
                .font(.subheadline)
                .foregroundStyle(PonderaTheme.textSecondary)
            Text("This is a reflection of what you’ve captured, not a diagnosis or a measure of importance.")
                .font(.caption)
                .foregroundStyle(PonderaTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .ponderaCard()
    }

    private var areaItems: [ExtractedItem] {
        items.filter {
            let corrected = $0.applyingCorrection(corrections[$0.id])
            return !corrected.isMarkedIncorrect && corrected.displayCategories.contains(category)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private var areaTopics: [ConsumerTopicSummary] {
        let itemIDs = Set(areaItems.map(\.id))
        return topics.compactMap { topic in
            let occurrences = ItemResolver.resolveItems(itemIds: topic.itemIds)
                .filter { itemIDs.contains($0.id) }
                .sorted { $0.createdAt > $1.createdAt }
            guard !occurrences.isEmpty else { return nil }
            return ConsumerTopicSummary(topic: topic, occurrences: occurrences)
        }
        .sorted { $0.mentionCount > $1.mentionCount }
        .prefix(4)
        .map { $0 }
    }

    private func loadData() {
        corrections = CorrectionsStore.shared.loadCorrections()
        items = ExtractionStore.shared.loadAllExtractions()
        topics = Array(TopicAggregateStore.shared.loadTopics().values)
    }
}
