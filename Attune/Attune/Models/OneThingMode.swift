import Foundation

enum OneThingModeFeature {
    static var isEnabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

struct OneThingModeState: Codable, Equatable {
    var focusedIntentionId: String?
    var activatedAt: Date?
    var lastExitedAt: Date?

    var isActive: Bool { focusedIntentionId != nil && activatedAt != nil }
    static let empty = OneThingModeState(focusedIntentionId: nil, activatedAt: nil, lastExitedAt: nil)
}

enum OneThingModePolicy {
    /// Focus eligibility starts only once the current active intentions exist.
    /// Using the newest creation date is conservative when intentions are added
    /// over time and prevents onboarding days from counting as quiet days.
    static func eligibilityStart(
        intentionSetStartedAt: Date,
        intentions: [Intention]
    ) -> Date? {
        guard let newestIntentionStartedAt = intentions.filter(\.isActive).map(\.createdAt).max() else {
            return nil
        }
        return max(intentionSetStartedAt, newestIntentionStartedAt)
    }

    static func shouldActivate(
        state: OneThingModeState,
        intentionSetStartedAt: Date,
        activeIntentionCount: Int,
        activityDateKeys: Set<String>,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Bool {
        guard !state.isActive, activeIntentionCount >= 2 else { return false }
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today) else { return false }
        let eligibilityStart = max(intentionSetStartedAt, state.lastExitedAt ?? .distantPast)
        guard eligibilityStart < twoDaysAgo else { return false }
        return !activityDateKeys.contains(dateKey(twoDaysAgo, calendar: calendar))
            && !activityDateKeys.contains(dateKey(yesterday, calendar: calendar))
    }

    static func replacementCandidate(
        intentions: [Intention],
        dailyTotals: [String: [Double]]
    ) -> Intention? {
        if let firstZero = intentions.first(where: { intention in
            let totals = dailyTotals[intention.id] ?? []
            return !totals.isEmpty && totals.allSatisfy { $0 <= 0 }
        }) { return firstZero }

        return intentions.enumerated().min { lhs, rhs in
            let left = averageCompletion(for: lhs.element, totals: dailyTotals[lhs.element.id] ?? [])
            let right = averageCompletion(for: rhs.element, totals: dailyTotals[rhs.element.id] ?? [])
            if left != right { return left < right }
            return lhs.offset < rhs.offset
        }?.element
    }

    private static func averageCompletion(for intention: Intention, totals: [Double]) -> Double {
        guard intention.targetValue > 0, !totals.isEmpty else { return 0 }
        return totals.map { min(max($0 / intention.targetValue, 0), 1) }.reduce(0, +) / Double(totals.count)
    }

    private static func dateKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
