//
//  CalendarFeature.swift
//  Pondera
//
//  Single visibility switch for the removable in-app Calendar experiment.
//

import Foundation

enum CalendarFeature {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif
}

struct CalendarCapture: Identifiable {
    let item: ExtractedItem
    let title: String
    let start: Date
    let end: Date?
    let isAllDay: Bool
    let hasSpecifiedTime: Bool
    let notes: String?

    var id: String { item.id }
}

struct CalendarUndatedCapture: Identifiable {
    let item: ExtractedItem
    let title: String
    let capturedAt: Date

    var id: String { item.id }
}

enum CalendarCaptureParser {
    static func captures(
        from items: [ExtractedItem],
        corrections: [String: ItemCorrection]
    ) -> [CalendarCapture] {
        items.compactMap { item in
            let correction = corrections[item.id]
            let corrected = item.applyingCorrection(correction)
            let schedule = effectiveSchedule(for: item, correction: correction)
            let isAllDay = schedule.isAllDay
            guard !corrected.isMarkedIncorrect,
                  corrected.displayType == ExtractedItem.ItemType.event,
                  schedule.isScheduled,
                  let startValue = schedule.startISO8601,
                  let start = isAllDay
                    ? (parseCalendarDay(startValue) ?? parseDate(startValue))
                    : parseDate(startValue) else {
                return nil
            }

            let candidate = item.calendarCandidate

            let correctedTitle = correction?.correctedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let suggestedTitle = candidate?.suggestedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title: String
            if let correctedTitle, !correctedTitle.isEmpty {
                title = correctedTitle
            } else if let suggestedTitle, !suggestedTitle.isEmpty {
                title = suggestedTitle
            } else {
                title = item.title
            }

            return CalendarCapture(
                item: item,
                title: title,
                start: start,
                end: schedule.endISO8601.flatMap { parseDate($0) },
                isAllDay: isAllDay,
                hasSpecifiedTime: schedule.hasSpecifiedTime,
                notes: candidate?.notes
            )
        }
        .sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    static func parseDate(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let internetFormatter = ISO8601DateFormatter()
        internetFormatter.formatOptions = [.withInternetDateTime]
        if let date = internetFormatter.date(from: value) {
            return date
        }

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = .current
        dayFormatter.dateFormat = "yyyy-MM-dd"
        return dayFormatter.date(from: value)
    }

    static func capture(
        for item: ExtractedItem,
        correction: ItemCorrection?
    ) -> CalendarCapture? {
        captures(from: [item], corrections: correction.map { [item.id: $0] } ?? [:]).first
    }

    static func undatedCaptures(
        from items: [ExtractedItem],
        corrections: [String: ItemCorrection]
    ) -> [CalendarUndatedCapture] {
        let datedIDs = Set(captures(from: items, corrections: corrections).map(\.id))
        return items.compactMap { item in
            let corrected = item.applyingCorrection(corrections[item.id])
            guard !corrected.isMarkedIncorrect,
                  corrected.displayType == ExtractedItem.ItemType.event,
                  !datedIDs.contains(item.id),
                  let capturedAt = parseDate(item.createdAt) else {
                return nil
            }
            return CalendarUndatedCapture(
                item: item,
                title: corrected.displayTitle,
                capturedAt: capturedAt
            )
        }
        .sorted { $0.capturedAt > $1.capturedAt }
    }

    private static func parseCalendarDay(_ value: String) -> Date? {
        guard value.count >= 10 else { return nil }
        return parseDate(String(value.prefix(10)))
    }


    private struct EffectiveSchedule {
        let isScheduled: Bool
        let startISO8601: String?
        let endISO8601: String?
        let isAllDay: Bool
        let hasSpecifiedTime: Bool
    }

    private static func effectiveSchedule(
        for item: ExtractedItem,
        correction: ItemCorrection?
    ) -> EffectiveSchedule {
        if let override = correction?.calendarSchedule {
            return EffectiveSchedule(
                isScheduled: override.isScheduled,
                startISO8601: override.startISO8601,
                endISO8601: override.endISO8601,
                isAllDay: false,
                hasSpecifiedTime: override.hasSpecifiedTime
            )
        }

        let startValue = item.calendarCandidate?.startISO8601
        let isAllDay = item.calendarCandidate?.isAllDay ?? false
        return EffectiveSchedule(
            isScheduled: startValue != nil,
            startISO8601: startValue,
            endISO8601: item.calendarCandidate?.endISO8601,
            isAllDay: isAllDay,
            hasSpecifiedTime: startValue?.contains("T") == true && !isAllDay
        )
    }
}
