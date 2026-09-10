//
//  InsightPatternsView.swift
//  Pondera
//

import SwiftUI

struct InsightPatternsView: View {
    let patterns: [InsightPattern]
    let items: [ExtractedItem]
    let corrections: [String: ItemCorrection]

    var body: some View {
        Group {
            if patterns.isEmpty {
                insightsEmptyState(
                    icon: "sparkles",
                    title: "Patterns will emerge here",
                    detail: "Keep talking naturally and recording your mood. Once Pondera has enough repeated evidence, it will show connections worth exploring."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Patterns in your reflections")
                            .font(.headline)
                            .foregroundStyle(PonderaTheme.textPrimary)

                        Text("These are observations from your captures and mood history—not diagnoses or fixed labels.")
                            .font(.caption)
                            .foregroundStyle(PonderaTheme.textSecondary)

                        ForEach(patterns) { pattern in
                            NavigationLink {
                                InsightPatternDetailView(
                                    pattern: pattern,
                                    items: items,
                                    corrections: corrections
                                )
                            } label: {
                                InsightPatternCard(pattern: pattern)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, PonderaTheme.horizontalPadding)
                    .padding(.vertical, 14)
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

private struct InsightPatternCard: View {
    let pattern: InsightPattern

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: pattern.icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(PonderaTheme.accentSecondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PonderaTheme.textTertiary)
            }

            Text(pattern.title)
                .font(.headline)
                .foregroundStyle(PonderaTheme.textPrimary)
                .multilineTextAlignment(.leading)

            Text(pattern.detail)
                .font(.subheadline)
                .foregroundStyle(PonderaTheme.textSecondary)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                Text(pattern.confidenceLabel)
                Text("·")
                Text("Based on \(pattern.sampleSize) \(pattern.sampleSize == 1 ? "capture" : "captures")")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(PonderaTheme.accent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ponderaCard()
    }
}

struct InsightPatternDetailView: View {
    let pattern: InsightPattern
    let items: [ExtractedItem]
    let corrections: [String: ItemCorrection]

    private var evidence: [ExtractedItem] {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return pattern.evidenceItemIDs.compactMap { byID[$0] }
            .filter { !$0.applyingCorrection(corrections[$0.id]).isMarkedIncorrect }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        ZStack {
            PonderaScreenBackground()
            ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        InsightPatternCard(pattern: pattern)
                    if !evidence.isEmpty {
                        Text("Evidence")
                            .font(.headline)
                            .foregroundStyle(PonderaTheme.textPrimary)
                        ForEach(evidence) { item in
                            InsightCaptureRow(item: item, correction: corrections[item.id])
                        }
                    } else {
                        Text("This pattern is based on your saved intention progress and daily mood history.")
                            .font(.caption)
                            .foregroundStyle(PonderaTheme.textSecondary)
                    }
                }
                .padding(.horizontal, PonderaTheme.horizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Pattern")
        .navigationBarTitleDisplayMode(.inline)
    }
}
