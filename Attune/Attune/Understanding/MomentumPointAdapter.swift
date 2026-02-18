//
//  MomentumPointAdapter.swift
//  Attune
//
//  Builds [MomentumPoint] for a selected day by processing check-ins
//  chronologically and computing cumulative % per intention at each check-in.
//  Does NOT apply overrides (raw progression from entries only).
//

import Foundation

/// Adapter that derives momentum chart data from CheckIn + ProgressEntry.
struct MomentumPointAdapter {

    /// Builds MomentumPoints for the given day. Uses check-ins + entries when available;
    /// falls back to entries-only (using entry.createdAt as timestamp) when no check-in linkage.
    /// - Parameters:
    ///   - dateKey: YYYY-MM-DD for the selected day
    ///   - intentionSet: Intention set active on that date
    ///   - intentions: Active intentions (for targetValue, title)
    ///   - checkIns: Check-ins for this day, sorted by createdAt ascending
    ///   - entries: Progress entries for this day
    static func buildPoints(
        dateKey: String,
        intentionSet: IntentionSet,
        intentions: [Intention],
        checkIns: [CheckIn],
        entries: [ProgressEntry]
    ) -> [MomentumPoint] {
        let checkInIds = Set(checkIns.map { $0.id }) // Debug: collect check-in ids to measure linkage
        let linkedEntriesCount = entries.filter { checkInIds.contains($0.sourceCheckInId) }.count // Debug: how many entries are linked to a known check-in
        // Try primary path: check-ins with linked entries
        let fromCheckIns = buildPointsFromCheckIns(
            dateKey: dateKey,
            intentionSet: intentionSet,
            intentions: intentions,
            checkIns: checkIns,
            entries: entries
        )
        if !fromCheckIns.isEmpty { // Debug: path succeeded using check-ins
            print("[Momentum] adapterPath=checkIns checkIns=\(checkIns.count) entries=\(entries.count) linkedEntries=\(linkedEntriesCount)") // Debug: log primary path usage
            return fromCheckIns // Debug: return check-in derived points
        }

        // Fallback: entries only (use entry.createdAt as timestamp)
        let fromEntriesOnly = buildPointsFromEntriesOnly(
            dateKey: dateKey,
            intentionSet: intentionSet,
            intentions: intentions,
            entries: entries
        )
        print("[Momentum] adapterPath=entriesOnly checkIns=\(checkIns.count) entries=\(entries.count) linkedEntries=\(linkedEntriesCount)") // Debug: log fallback path usage
        return fromEntriesOnly // Debug: return entries-only points
    }

    /// Primary: one point per (check-in, intention) when check-ins have linked entries.
    private static func buildPointsFromCheckIns(
        dateKey: String,
        intentionSet: IntentionSet,
        intentions: [Intention],
        checkIns: [CheckIn],
        entries: [ProgressEntry]
    ) -> [MomentumPoint] {
        let intentionIndexById = Dictionary(
            uniqueKeysWithValues: intentions.enumerated().map { ($1.id, $0) }
        )
        let entriesByCheckIn = Dictionary(grouping: entries) { $0.sourceCheckInId }
            .mapValues { $0.sorted { $0.createdAt < $1.createdAt } }

        var points: [MomentumPoint] = []
        var totalsByIntention: [String: Double] = [:]

        for checkIn in checkIns {
            guard let checkInEntries = entriesByCheckIn[checkIn.id], !checkInEntries.isEmpty else {
                continue
            }
            for entry in checkInEntries {
                switch entry.updateType {
                case "TOTAL":
                    totalsByIntention[entry.intentionId] = entry.amount
                case "INCREMENT":
                    totalsByIntention[entry.intentionId] = (totalsByIntention[entry.intentionId] ?? 0) + entry.amount
                default:
                    break
                }
            }
            let updatedIntentions = checkInEntries.map { $0.intentionId }
            let withPercent: [(intentionId: String, percent: Double)] = updatedIntentions.compactMap { intentionId in
                guard let intention = intentions.first(where: { $0.id == intentionId }),
                      intention.targetValue > 0 else { return nil }
                let total = totalsByIntention[intentionId] ?? 0
                let effectiveTarget: Double
                if intention.timeframe.lowercased() == "weekly" {
                    effectiveTarget = intention.targetValue / 7.0
                } else {
                    effectiveTarget = intention.targetValue
                }
                let percent = (total / effectiveTarget) * 100.0
                return (intentionId, percent)
            }
            let sorted = withPercent.sorted { $0.percent > $1.percent }
            let offsets: [Double] = [60, 30, 0]
            for (idx, item) in sorted.enumerated() {
                let offset = idx < offsets.count ? offsets[idx] : 0
                let intention = intentions.first(where: { $0.id == item.intentionId })!
                let colorIdx = intentionIndexById[intention.id] ?? 0
                points.append(MomentumPoint(
                    id: "\(checkIn.id)-\(intention.id)",
                    date: checkIn.createdAt,
                    intentionId: intention.id,
                    intentionTitle: intention.title,
                    colorIndex: colorIdx,
                    percent: item.percent,
                    timeOffsetSeconds: offset
                ))
            }
        }
        return points
    }

    /// Fallback: entries only. Use entry.createdAt as timestamp; group by minute to batch.
    private static func buildPointsFromEntriesOnly(
        dateKey: String,
        intentionSet: IntentionSet,
        intentions: [Intention],
        entries: [ProgressEntry]
    ) -> [MomentumPoint] {
        let intentionIndexById = Dictionary(
            uniqueKeysWithValues: intentions.enumerated().map { ($1.id, $0) }
        )
        let sortedEntries = entries.sorted { $0.createdAt < $1.createdAt }
        var points: [MomentumPoint] = []
        var totalsByIntention: [String: Double] = [:]

        for entry in sortedEntries {
            switch entry.updateType {
            case "TOTAL":
                totalsByIntention[entry.intentionId] = entry.amount
            case "INCREMENT":
                totalsByIntention[entry.intentionId] = (totalsByIntention[entry.intentionId] ?? 0) + entry.amount
            default:
                break
            }
            guard let intention = intentions.first(where: { $0.id == entry.intentionId }),
                  intention.targetValue > 0 else { continue }
            let total = totalsByIntention[entry.intentionId] ?? 0
            let effectiveTarget: Double
            if intention.timeframe.lowercased() == "weekly" {
                effectiveTarget = intention.targetValue / 7.0
            } else {
                effectiveTarget = intention.targetValue
            }
            let percent = (total / effectiveTarget) * 100.0
            let colorIdx = intentionIndexById[intention.id] ?? 0
            points.append(MomentumPoint(
                id: "\(entry.id)-\(intention.id)",
                date: entry.createdAt,
                intentionId: intention.id,
                intentionTitle: intention.title,
                colorIndex: colorIdx,
                percent: percent,
                timeOffsetSeconds: 0
            ))
        }
        return points
    }

    /// Returns dates for Mon–Sun of the week containing the given date.
    static func weekDays(containing date: Date) -> [Date] {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        // Monday = 1 in (weekday + 5) % 7 when weekday is 2=Mon
        let weekday = cal.component(.weekday, from: date)
        let daysFromMonday = (weekday + 5) % 7
        guard let monday = cal.date(byAdding: .day, value: -daysFromMonday, to: startOfDay) else {
            return []
        }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    /// Max percent across points for Y-axis cap. If any > 100, cap at 150; else 100.
    static func yAxisMax(for points: [MomentumPoint]) -> Double {
        let maxPct = points.map { $0.percent }.max() ?? 0
        return maxPct > 100 ? 150 : 100
    }
}
