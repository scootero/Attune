//
//  TopicDetailView.swift
//  Pondera
//
//  Consumer detail for a grouped theme and the user's visible mentions.
//

import SwiftUI

struct TopicDetailView: View {
    let topic: TopicAggregate

    @State private var occurrences: [ExtractedItem] = []
    @State private var corrections: [String: ItemCorrection] = [:]

    var body: some View {
        ZStack {
            PonderaScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    topicHeader

                    if visibleOccurrences.isEmpty {
                        insightsEmptyState(
                            icon: "eye.slash",
                            title: "No visible captures",
                            detail: "Captures you hide during review are removed from this theme."
                        )
                        .padding(.horizontal, -PonderaTheme.horizontalPadding)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(visibleOccurrences.count == 1 ? "Mention" : "Mentions")
                                .font(.headline)
                                .foregroundStyle(PonderaTheme.textPrimary)

                            ForEach(visibleOccurrences) { item in
                                NavigationLink(destination: InsightDetailView(item: item)) {
                                    InsightCaptureRow(item: item, correction: corrections[item.id])
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, PonderaTheme.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadData)
    }

    private var topicHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                visibleOccurrences.count > 1 ? "Recurring theme" : "Mentioned once",
                systemImage: visibleOccurrences.count > 1 ? "repeat" : "circle.dotted"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(PonderaTheme.accentSecondary)

            Text(topic.displayTitle)
                .font(.title2.bold())
                .foregroundStyle(PonderaTheme.textPrimary)

            Text("\(visibleOccurrences.count) \(visibleOccurrences.count == 1 ? "mention" : "mentions") · Last mentioned \(InsightDisplay.relativeDate(topic.lastSeenAtISO))")
                .font(.subheadline)
                .foregroundStyle(PonderaTheme.textSecondary)

            if !topic.categories.isEmpty {
                HStack(spacing: 8) {
                    ForEach(topic.categories.prefix(3), id: \.self) { category in
                        Label(InsightDisplay.categoryLabel(category), systemImage: InsightDisplay.categoryIcon(category))
                            .font(.caption)
                            .foregroundStyle(PonderaTheme.textSecondary)
                    }
                }
            }

            Text("Pondera groups related captures into a theme. A theme does not change Today’s progress or create a tracked intention.")
                .font(.caption)
                .foregroundStyle(PonderaTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .ponderaCard()
    }

    private var visibleOccurrences: [ExtractedItem] {
        occurrences.filter { !($0.applyingCorrection(corrections[$0.id]).isMarkedIncorrect) }
    }

    private func loadData() {
        corrections = CorrectionsStore.shared.loadCorrections()
        occurrences = ItemResolver.resolveItems(itemIds: topic.itemIds)
            .sorted { $0.createdAt > $1.createdAt }
    }
}

#Preview {
    NavigationStack {
        TopicDetailView(
            topic: TopicAggregate(
                canonicalKey: "exercise__abc123",
                displayTitle: "Exercise",
                firstSeenAtISO: ISO8601DateFormatter().string(from: Date()),
                categories: [ExtractedItem.Category.fitnessHealth],
                itemId: "sample-id"
            )
        )
    }
}
