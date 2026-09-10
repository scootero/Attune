//
//  LifeAreaSummary.swift
//  Pondera
//
//  Read-only category activity used by the Insights life constellation.
//

import Foundation

enum LifeAreaPeriod: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case allTime

    var id: Self { self }

    var label: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .allTime: return "All time"
        }
    }

    func contains(_ date: Date, referenceDate: Date, calendar: Calendar) -> Bool {
        switch self {
        case .day:
            return calendar.isDate(date, inSameDayAs: referenceDate)
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else { return false }
            return interval.contains(date)
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: referenceDate) else { return false }
            return interval.contains(date)
        case .allTime:
            return true
        }
    }
}

struct LifeAreaSummary: Identifiable, Equatable {
    let category: String
    let mentionCount: Int
    let intentionCount: Int
    let sessionCount: Int
    let itemIDs: [String]
    let lastSeenAt: String

    var id: String { category }
}

enum LifeAreaSummaryBuilder {
    static func make(
        from items: [ExtractedItem],
        corrections: [String: ItemCorrection] = [:],
        period: LifeAreaPeriod = .allTime,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [LifeAreaSummary] {
        struct Accumulator {
            var itemIDs: [String] = []
            var intentionCount = 0
            var sessionIDs = Set<String>()
            var lastSeenAt = ""
        }

        var grouped: [String: Accumulator] = [:]

        for item in items {
            if period != .allTime {
                guard let createdAt = parseDate(item.createdAt),
                      period.contains(createdAt, referenceDate: referenceDate, calendar: calendar) else {
                    continue
                }
            }
            let corrected = item.applyingCorrection(corrections[item.id])
            guard !corrected.isMarkedIncorrect else { continue }

            // Count a category once per capture, even if the source contains duplicates.
            for category in Set(corrected.displayCategories) where !category.isEmpty {
                var accumulator = grouped[category, default: Accumulator()]
                if !accumulator.itemIDs.contains(item.id) {
                    accumulator.itemIDs.append(item.id)
                }
                if corrected.displayType == ExtractedItem.ItemType.intention {
                    accumulator.intentionCount += 1
                }
                accumulator.sessionIDs.insert(item.sessionId)
                if item.createdAt > accumulator.lastSeenAt {
                    accumulator.lastSeenAt = item.createdAt
                }
                grouped[category] = accumulator
            }
        }

        return grouped.map { category, accumulator in
            LifeAreaSummary(
                category: category,
                mentionCount: accumulator.itemIDs.count,
                intentionCount: accumulator.intentionCount,
                sessionCount: accumulator.sessionIDs.count,
                itemIDs: accumulator.itemIDs,
                lastSeenAt: accumulator.lastSeenAt
            )
        }
        .sorted {
            if $0.sessionCount != $1.sessionCount { return $0.sessionCount > $1.sessionCount }
            if $0.mentionCount != $1.mentionCount { return $0.mentionCount > $1.mentionCount }
            return $0.category < $1.category
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
