//
//  InsightPatternModule.swift
//  Pondera
//
//  A small, read-only pattern layer for Insights. It deliberately produces
//  associations from persisted evidence rather than personality or health
//  conclusions. A future server/AI provider can implement the same output.
//

import Foundation

struct InsightPattern: Identifiable {
    enum Kind: Equatable {
        case moodAndTheme
        case recurringTheme
    }

    let id: String
    let kind: Kind
    let title: String
    let detail: String
    let evidenceItemIDs: [String]
    let sampleSize: Int
    let confidenceLabel: String
    let icon: String
}

enum InsightPatternBuilder {
    static func make(
        items: [ExtractedItem],
        topics: [TopicAggregate],
        moods: [DailyMood],
        corrections: [String: ItemCorrection] = [:]
    ) -> [InsightPattern] {
        let visibleItems = items.filter {
            !$0.applyingCorrection(corrections[$0.id]).isMarkedIncorrect
        }
        let itemsByID = Dictionary(uniqueKeysWithValues: visibleItems.map { ($0.id, $0) })
        let moodByDate = Dictionary(uniqueKeysWithValues: moods.compactMap { mood in
            mood.moodScore.map { (mood.dateKey, $0) }
        })
        let scoredMoods = Array(moodByDate.values)
        guard !visibleItems.isEmpty else { return [] }

        var patterns: [InsightPattern] = []
        for topic in topics {
            let occurrences = topic.itemIds.compactMap { itemsByID[$0] }
            guard !occurrences.isEmpty else { continue }

            let datesWithMood = occurrences.compactMap { item -> (ExtractedItem, Int)? in
                guard let date = dateKey(for: item.createdAt), let mood = moodByDate[date] else { return nil }
                return (item, mood)
            }

            if datesWithMood.count >= 3, scoredMoods.count >= 3 {
                let themeAverage = average(datesWithMood.map { $0.1 })
                let overallAverage = average(scoredMoods)
                let difference = themeAverage - overallAverage
                if abs(difference) >= 1.0 {
                    let direction = difference > 0 ? "higher" : "lower"
                    patterns.append(InsightPattern(
                        id: "mood-theme-\(topic.id)",
                        kind: .moodAndTheme,
                        title: "Mood runs \(direction) around \(topic.displayTitle.lowercased())",
                        detail: "Your mood averaged \(formatted(themeAverage))/10 on days this theme appeared, compared with \(formatted(overallAverage))/10 across your recorded days.",
                        evidenceItemIDs: datesWithMood.map { $0.0.id },
                        sampleSize: datesWithMood.count,
                        confidenceLabel: datesWithMood.count >= 5 ? "Steady signal" : "Early signal",
                        icon: difference > 0 ? "arrow.up.right.circle" : "arrow.down.right.circle"
                    ))
                }
            }

            if occurrences.count >= 3 {
                patterns.append(InsightPattern(
                    id: "recurring-\(topic.id)",
                    kind: .recurringTheme,
                    title: "\(topic.displayTitle) keeps returning",
                    detail: "You mentioned this across \(Set(occurrences.map { $0.sessionId }).count) conversations and \(occurrences.count) captures.",
                    evidenceItemIDs: occurrences.map { $0.id },
                    sampleSize: occurrences.count,
                    confidenceLabel: "Observed pattern",
                    icon: "repeat.circle"
                ))
            }
        }

        return patterns.sorted { lhs, rhs in
            if lhs.kindOrder != rhs.kindOrder { return lhs.kindOrder < rhs.kindOrder }
            return lhs.sampleSize > rhs.sampleSize
        }.prefix(3).map { $0 }
    }

    /// Builds intention-specific associations from the existing progress and
    /// daily mood records. Progress is evidence that the intention was acted
    /// on that day; mood is always the latest saved observation for that date.
    static func makeIntentionPatterns(
        intentions: [Intention],
        progressEntries: [ProgressEntry],
        moods: [DailyMood]
    ) -> [InsightPattern] {
        let moodByDate = Dictionary(uniqueKeysWithValues: moods.compactMap { mood in
            mood.moodScore.map { (mood.dateKey, $0) }
        })
        let allMoodScores = Array(moodByDate.values)
        guard allMoodScores.count >= 3 else { return [] }

        return intentions.filter(\.isActive).compactMap { intention in
            let progress = progressEntries.filter { $0.intentionId == intention.id }
            let progressDates = Array(Set(progress.map(\.dateKey))).sorted()
            let progressMoodScores = progressDates.compactMap { moodByDate[$0] }
            guard progressMoodScores.count >= 3 else { return nil }

            let intentionAverage = average(progressMoodScores)
            let overallAverage = average(allMoodScores)
            let difference = intentionAverage - overallAverage
            guard abs(difference) >= 1.0 else { return nil }

            let direction = difference > 0 ? "higher" : "lower"
            return InsightPattern(
                id: "mood-intention-\(intention.id)",
                kind: .moodAndTheme,
                title: "Mood runs \(direction) on \(intention.title.lowercased()) days",
                detail: "Your mood averaged \(formatted(intentionAverage))/10 on days you recorded progress for this intention, compared with \(formatted(overallAverage))/10 across your recorded days.",
                evidenceItemIDs: [],
                sampleSize: progressMoodScores.count,
                confidenceLabel: progressMoodScores.count >= 5 ? "Steady signal" : "Early signal",
                icon: difference > 0 ? "arrow.up.right.circle" : "arrow.down.right.circle"
            )
        }
    }

    private static func dateKey(for value: String) -> String? {
        guard let date = ISO8601DateFormatter().date(from: value) else { return nil }
        return AppPaths.dateKey(from: date)
    }

    private static func average(_ values: [Int]) -> Double {
        Double(values.reduce(0, +)) / Double(values.count)
    }

    private static func formatted(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

private extension InsightPattern {
    var kindOrder: Int {
        switch kind {
        case .moodAndTheme: return 0
        case .recurringTheme: return 1
        }
    }
}
