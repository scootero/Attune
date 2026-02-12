//
//  ProgressDataHelper.swift
//  Attune
//
//  Helper to load and structure progress data for the Progress tab.
//  Reads only from Intentions/CheckIns/ProgressEntries/Mood stores. Slice 6.
//

import Foundation

/// Row for Daily Totals list
struct DayRow: Identifiable {
    let dateKey: String
    let date: Date
    let overallPercent: Double
    let moodLabel: String?
    let intentionSet: IntentionSet?
    
    var id: String { dateKey }
}

/// Row for Per Goal list (single intention)
struct IntentionRow: Identifiable {
    let intention: Intention
    let intentionSet: IntentionSet
    
    var id: String { intention.id }
}

/// Data for a single day's detail (intentions + entries + check-ins). Slice 7: includes overrides.
struct DayDetailData {
    let dateKey: String
    let date: Date
    let intentionSet: IntentionSet?
    let intentions: [Intention]
    let entriesByIntentionId: [String: [ProgressEntry]]
    let checkIns: [CheckIn]
    let mood: DailyMood?
    /// Override amount per intentionId (Slice 7). Takes precedence over entries.
    let overridesByIntentionId: [String: Double]
    
    var overallPercent: Double {
        guard let set = intentionSet, !intentions.isEmpty else { return 0 }
        var totals: [String: Double] = [:]
        let allEntries = entriesByIntentionId.values.flatMap { $0 }
        for intention in intentions {
            let override = overridesByIntentionId[intention.id]
            let total = ProgressCalculator.totalForIntention(
                entries: allEntries,
                dateKey: dateKey,
                intentionId: intention.id,
                intentionSetId: set.id,
                overrideAmount: override
            )
            totals[intention.id] = total
        }
        return ProgressCalculator.overallPercentComplete(intentions: intentions, totalsByIntentionId: totals)
    }
    
    func totalForIntention(_ intention: Intention) -> Double {
        guard let set = intentionSet else { return 0 }
        let entries = entriesByIntentionId[intention.id] ?? []
        let override = overridesByIntentionId[intention.id]
        return ProgressCalculator.totalForIntention(
            entries: entries,
            dateKey: dateKey,
            intentionId: intention.id,
            intentionSetId: set.id,
            overrideAmount: override
        )
    }
    
    func percentForIntention(_ intention: Intention) -> Double {
        let total = totalForIntention(intention)
        return ProgressCalculator.percentComplete(
            total: total,
            targetValue: intention.targetValue,
            timeframe: intention.timeframe
        )
    }
}

/// Data for IntentionDetail (one intention, last 7 days)
struct IntentionDetailData {
    let intention: Intention
    let intentionSet: IntentionSet
    let dayRows: [(dateKey: String, date: Date, total: Double, percent: Double)]
}

@MainActor
struct ProgressDataHelper {
    
    private static let daysToShow = 7
    
    /// Last 7 date keys (today first)
    static func last7DateKeys() -> [(dateKey: String, date: Date)] {
        let calendar = Calendar.current
        return (0..<daysToShow).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            return (ProgressCalculator.dateKey(for: date), date)
        }
    }
    
    /// Daily Totals rows for last 7 days
    static func loadDayRows() -> [DayRow] {
        let sets = IntentionSetStore.shared.loadAllIntentionSets()
        let intentionsBySetId = loadIntentionsBySetId(sets: sets)
        let entriesBySetAndDate = loadEntriesBySetAndDate()
        let checkInsBySetAndDate = loadCheckInsBySetAndDate()
        
        return last7DateKeys().map { dateKey, date in
            let set = StreakCalculator.intentionSetActive(on: dateKey, from: sets)
            let intentions = (set.map { intentionsBySetId[$0.id] ?? [] }) ?? []
            
            var entries: [ProgressEntry] = []
            if let s = set {
                entries = entriesBySetAndDate["\(s.id)|\(dateKey)"] ?? []
            }
            
            let overrides = OverrideStore.shared.loadOverridesForDate(dateKey: dateKey)
            
            var totalsByIntentionId: [String: Double] = [:]
            if let s = set {
                for intention in intentions {
                    let override = overrides[intention.id]
                    let total = ProgressCalculator.totalForIntention(
                        entries: entries,
                        dateKey: dateKey,
                        intentionId: intention.id,
                        intentionSetId: s.id,
                        overrideAmount: override
                    )
                    totalsByIntentionId[intention.id] = total
                }
            }
            
            let overall = ProgressCalculator.overallPercentComplete(
                intentions: intentions,
                totalsByIntentionId: totalsByIntentionId
            )
            
            let mood = DailyMoodStore.shared.loadDailyMood(dateKey: dateKey)
            
            return DayRow(
                dateKey: dateKey,
                date: date,
                overallPercent: overall,
                moodLabel: mood?.moodLabel,
                intentionSet: set
            )
        }
    }
    
    /// Per Goal rows (current intentions)
    static func loadIntentionRows() -> [IntentionRow] {
        guard let set = try? IntentionSetStore.shared.loadOrCreateCurrentIntentionSet() else {
            return []
        }
        let intentions = IntentionStore.shared.loadIntentions(ids: set.intentionIds)
            .filter { $0.isActive }
        return intentions.map { IntentionRow(intention: $0, intentionSet: set) }
    }
    
    /// Full day detail data for DayDetailView
    static func loadDayDetail(dateKey: String) -> DayDetailData {
        let date = Self.date(from: dateKey) ?? Date()
        let sets = IntentionSetStore.shared.loadAllIntentionSets()
        guard let set = StreakCalculator.intentionSetActive(on: dateKey, from: sets) else {
            return DayDetailData(
                dateKey: dateKey,
                date: date,
                intentionSet: nil,
                intentions: [],
                entriesByIntentionId: [:],
                checkIns: [],
                mood: DailyMoodStore.shared.loadDailyMood(dateKey: dateKey),
                overridesByIntentionId: OverrideStore.shared.loadOverridesForDate(dateKey: dateKey)
            )
        }
        
        let intentions = IntentionStore.shared.loadIntentions(ids: set.intentionIds)
            .filter { $0.isActive }
        let entries = ProgressStore.shared.loadEntries(dateKey: dateKey, intentionSetId: set.id)
        let checkIns = CheckInStore.shared.loadCheckIns(intentionSetId: set.id, dateKey: dateKey)
        
        var entriesByIntentionId: [String: [ProgressEntry]] = [:]
        for entry in entries {
            entriesByIntentionId[entry.intentionId, default: []].append(entry)
        }
        for (id, list) in entriesByIntentionId {
            entriesByIntentionId[id] = list.sorted { $0.createdAt < $1.createdAt }
        }
        
        let mood = DailyMoodStore.shared.loadDailyMood(dateKey: dateKey)
        let overrides = OverrideStore.shared.loadOverridesForDate(dateKey: dateKey)
        
        return DayDetailData(
            dateKey: dateKey,
            date: date,
            intentionSet: set,
            intentions: intentions,
            entriesByIntentionId: entriesByIntentionId,
            checkIns: checkIns.sorted { $0.createdAt < $1.createdAt },
            mood: mood,
            overridesByIntentionId: overrides
        )
    }
    
    /// Intention detail (one intention, last 7 days).
    /// For each day, uses the IntentionSet active on that date (may differ from current).
    static func loadIntentionDetail(intention: Intention, intentionSet: IntentionSet) -> IntentionDetailData {
        let sets = IntentionSetStore.shared.loadAllIntentionSets()
        var dayRows: [(dateKey: String, date: Date, total: Double, percent: Double)] = []
        
        for (dateKey, date) in last7DateKeys() {
            guard let activeSet = StreakCalculator.intentionSetActive(on: dateKey, from: sets),
                  activeSet.intentionIds.contains(intention.id) else {
                dayRows.append((dateKey, date, 0, 0))
                continue
            }
            
            let entries = ProgressStore.shared.loadEntries(dateKey: dateKey, intentionSetId: activeSet.id)
            let override = OverrideStore.shared.loadOverridesForDate(dateKey: dateKey)[intention.id]
            let total = ProgressCalculator.totalForIntention(
                entries: entries,
                dateKey: dateKey,
                intentionId: intention.id,
                intentionSetId: activeSet.id,
                overrideAmount: override
            )
            let percent = ProgressCalculator.percentComplete(
                total: total,
                targetValue: intention.targetValue,
                timeframe: intention.timeframe
            )
            dayRows.append((dateKey, date, total, percent))
        }
        
        return IntentionDetailData(
            intention: intention,
            intentionSet: intentionSet,
            dayRows: dayRows
        )
    }
    
    private static func loadIntentionsBySetId(sets: [IntentionSet]) -> [String: [Intention]] {
        var result: [String: [Intention]] = [:]
        for set in sets {
            result[set.id] = IntentionStore.shared.loadIntentions(ids: set.intentionIds)
                .filter { $0.isActive }
        }
        return result
    }
    
    private static func loadEntriesBySetAndDate() -> [String: [ProgressEntry]] {
        var result: [String: [ProgressEntry]] = [:]
        for entry in ProgressStore.shared.loadAllProgressEntries() {
            let key = "\(entry.intentionSetId)|\(entry.dateKey)"
            result[key, default: []].append(entry)
        }
        return result
    }
    
    private static func loadCheckInsBySetAndDate() -> [String: [CheckIn]] {
        var result: [String: [CheckIn]] = [:]
        for checkIn in CheckInStore.shared.loadAllCheckIns() {
            let dateKey = AppPaths.dateKey(from: checkIn.createdAt)
            let key = "\(checkIn.intentionSetId)|\(dateKey)"
            result[key, default: []].append(checkIn)
        }
        return result
    }
    
    private static func date(from dateKey: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: dateKey)
    }
}
