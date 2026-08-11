//
//  SessionRecapBuilder.swift
//  Attune
//
//  Pure, read-only derivation of a truthful recap from existing session data.
//

import Foundation

struct SessionRecap: Equatable {
    let headline: String
    let quote: String?
}

enum SessionRecapBuilder {
    static func makeRecap(
        currentSession: Session,
        currentItems: [ExtractedItem],
        allSessions: [Session],
        allItems: [ExtractedItem],
        topics: [TopicAggregate],
        corrections: [String: ItemCorrection],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> SessionRecap {
        let eligibleCurrentItems = currentItems.filter {
            !$0.applyingCorrection(corrections[$0.id]).isMarkedIncorrect
        }

        let headline = recurringTopicHeadline(
            currentSession: currentSession,
            eligibleCurrentItems: eligibleCurrentItems,
            allSessions: allSessions,
            allItems: allItems,
            topics: topics,
            corrections: corrections,
            calendar: calendar,
            now: now
        ) ?? commitmentHeadline(
            items: eligibleCurrentItems,
            corrections: corrections
        ) ?? neutralHeadline(itemCount: eligibleCurrentItems.count)

        return SessionRecap(
            headline: headline,
            quote: selectedQuote(from: currentItems, corrections: corrections)
        )
    }

    static func selectedQuote(
        from items: [ExtractedItem],
        corrections: [String: ItemCorrection]
    ) -> String? {
        let candidates = items.compactMap { item -> (item: ExtractedItem, date: Date, quote: String)? in
            let corrected = item.applyingCorrection(corrections[item.id])
            guard !corrected.isMarkedIncorrect,
                  corrected.displayType == ExtractedItem.ItemType.intention
                    || corrected.displayType == ExtractedItem.ItemType.commitment,
                  let date = parseISO8601(item.extractedAt) else {
                return nil
            }

            let quote = normalizeWhitespace(item.sourceQuote)
            guard !quote.isEmpty else { return nil }
            return (item, date, quote)
        }

        guard let selected = candidates.sorted(by: { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.item.id < rhs.item.id
        }).first else {
            return nil
        }

        return truncateQuote(selected.quote, maximumCharacterCount: 100)
    }

    static func normalizeWhitespace(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func truncateQuote(_ quote: String, maximumCharacterCount: Int) -> String {
        let normalized = normalizeWhitespace(quote)
        guard maximumCharacterCount > 0, normalized.count > maximumCharacterCount else {
            return normalized
        }

        guard maximumCharacterCount > 1 else { return "…" }
        let contentLimit = maximumCharacterCount - 1
        var words: [Substring] = []
        var characterCount = 0

        for word in normalized.split(separator: " ") {
            let proposedCount = characterCount + (words.isEmpty ? 0 : 1) + word.count
            guard proposedCount <= contentLimit else { break }
            words.append(word)
            characterCount = proposedCount
        }

        guard !words.isEmpty else { return "…" }
        return words.joined(separator: " ") + "…"
    }

    private static func recurringTopicHeadline(
        currentSession: Session,
        eligibleCurrentItems: [ExtractedItem],
        allSessions: [Session],
        allItems: [ExtractedItem],
        topics: [TopicAggregate],
        corrections: [String: ItemCorrection],
        calendar: Calendar,
        now: Date
    ) -> String? {
        guard let month = calendar.dateInterval(of: .month, for: now) else { return nil }

        let currentItemIds = Set(eligibleCurrentItems.map(\.id))
        let itemsById = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        let sessionsById = Dictionary(uniqueKeysWithValues: allSessions.map { ($0.id, $0) })

        let candidates: [(topic: TopicAggregate, sessionCount: Int)] = topics.compactMap { topic in
            guard !topic.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !topic.itemIds.isEmpty else {
                return nil
            }

            // Topic membership is frozen when extraction occurs. A later title or
            // category correction can invalidate that grouping, so skip it rather
            // than presenting a statement that may no longer be literally true.
            let hasGroupingCorrection = topic.itemIds.contains { itemId in
                guard let correction = corrections[itemId] else { return false }
                return correction.correctedTitle != nil || correction.correctedCategories != nil
            }
            guard !hasGroupingCorrection else { return nil }

            // Orphaned IDs make the stored evidence incomplete and therefore
            // unsuitable for a factual recurring-topic claim.
            let resolvedItems = topic.itemIds.compactMap { itemsById[$0] }
            guard resolvedItems.count == topic.itemIds.count else { return nil }

            let eligibleItems = resolvedItems.filter {
                !$0.applyingCorrection(corrections[$0.id]).isMarkedIncorrect
            }
            guard eligibleItems.contains(where: { currentItemIds.contains($0.id) }) else {
                return nil
            }

            let sessionIds = Set(eligibleItems.compactMap { item -> String? in
                guard let session = sessionsById[item.sessionId],
                      month.contains(session.startedAt) else {
                    return nil
                }
                return session.id
            })

            guard sessionIds.contains(currentSession.id),
                  sessionIds.count >= 2,
                  sessionIds.contains(where: { sessionId in
                      guard let session = sessionsById[sessionId] else { return false }
                      return session.startedAt < currentSession.startedAt
                  }) else {
                return nil
            }

            return (topic, sessionIds.count)
        }

        guard let best = candidates.sorted(by: { lhs, rhs in
            if lhs.sessionCount != rhs.sessionCount { return lhs.sessionCount > rhs.sessionCount }
            let titleOrder = lhs.topic.displayTitle.localizedCaseInsensitiveCompare(rhs.topic.displayTitle)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.topic.canonicalKey < rhs.topic.canonicalKey
        }).first else {
            return nil
        }

        return "You mentioned \(best.topic.displayTitle) across \(best.sessionCount) sessions this month."
    }

    private static func commitmentHeadline(
        items: [ExtractedItem],
        corrections: [String: ItemCorrection]
    ) -> String? {
        let count = items.filter {
            $0.applyingCorrection(corrections[$0.id]).displayType == ExtractedItem.ItemType.commitment
        }.count
        guard count > 0 else { return nil }

        if count == 1 { return "One thing you said you’d do." }
        if count == 2 { return "Two things you said you’d do." }
        return "\(count) things you said you’d do."
    }

    private static func neutralHeadline(itemCount: Int) -> String {
        switch itemCount {
        case 0: return "Nothing new was captured."
        case 1: return "1 thing worth remembering."
        default: return "\(itemCount) things worth remembering."
        }
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}
