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
            return deduplicateByMinuteBucket(from: fromCheckIns) // Combine same-intention same-minute duplicates, keep max %
        }

        // Fallback: entries only (use entry.createdAt as timestamp)
        let fromEntriesOnly = buildPointsFromEntriesOnly(
            dateKey: dateKey,
            intentionSet: intentionSet,
            intentions: intentions,
            entries: entries
        )
        print("[Momentum] adapterPath=entriesOnly checkIns=\(checkIns.count) entries=\(entries.count) linkedEntries=\(linkedEntriesCount)") // Debug: log fallback path usage
        return deduplicateByMinuteBucket(from: fromEntriesOnly) // Combine same-intention same-minute duplicates, keep max %
    }

    /// Buckets points by (intentionId, minute) and keeps one bar per bucket with max percent.
    /// Fixes stacked bars when multiple check-ins for same intention occur within the same minute.
    /// Uses max percent within bucket (robust when users repeat themselves).
    private static func deduplicateByMinuteBucket(from points: [MomentumPoint]) -> [MomentumPoint] {
        let cal = Calendar.current
        // Group by (intentionId, minute-bucket). Bucket = year, month, day, hour, minute (truncate seconds).
        var bucketToPoints: [String: [MomentumPoint]] = [:]
        for point in points {
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: point.date)
            guard let bucketDate = cal.date(from: comps) else { continue }
            let key = "\(point.intentionId)-\(bucketDate.timeIntervalSince1970)"
            bucketToPoints[key, default: []].append(point)
        }
        // For each bucket: keep single point with max percent; use bucket timestamp as date for consistent x-position.
        var result: [MomentumPoint] = []
        for (_, group) in bucketToPoints {
            guard let best = group.max(by: { $0.percent < $1.percent }) else { continue }
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: best.date)
            let bucketDate = cal.date(from: comps) ?? best.date
            let stableId = "\(best.intentionId)-\(Int(bucketDate.timeIntervalSince1970))"
            result.append(MomentumPoint(
                id: stableId,
                date: bucketDate,
                intentionId: best.intentionId,
                intentionTitle: best.intentionTitle,
                colorIndex: best.colorIndex,
                percent: best.percent,
                timeOffsetSeconds: best.timeOffsetSeconds
            ))
        }
        return result.sorted { $0.date < $1.date }
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
        ) // map intention ids to color indexes
        let checkInIds = Set(checkIns.map { $0.id }) // set for linked-entry filtering
        let linkedEntries = entries.filter { checkInIds.contains($0.sourceCheckInId) } // only use entries tied to provided check-ins
        let sortedEntries = linkedEntries.sorted { $0.effectiveTookPlaceAt < $1.effectiveTookPlaceAt } // enforce global chronological order by effective time

        var points: [MomentumPoint] = [] // accumulated chart points
        var totalsByIntention: [String: Double] = [:] // running totals for percent calculations

        for entry in sortedEntries { // walk entries in chronological order
            switch entry.updateType { // update cumulative totals
            case "TOTAL":
                totalsByIntention[entry.intentionId] = entry.amount // set total directly
            case "INCREMENT":
                totalsByIntention[entry.intentionId] = (totalsByIntention[entry.intentionId] ?? 0) + entry.amount // add increment
            default:
                break // ignore unknown types
            }
            guard let intention = intentions.first(where: { $0.id == entry.intentionId }), // find intention metadata
                  intention.targetValue > 0 else { continue } // skip if no target to compute percent
            let total = totalsByIntention[entry.intentionId] ?? 0 // current cumulative total
            let effectiveTarget: Double // denominator for percent
            if intention.timeframe.lowercased() == "weekly" { // weekly targets divide across days
                effectiveTarget = intention.targetValue / 7.0 // daily target for weekly intentions
            } else {
                effectiveTarget = intention.targetValue // daily target for non-weekly
            }
            let percent = (total / effectiveTarget) * 100.0 // compute completion percent
            let colorIdx = intentionIndexById[intention.id] ?? 0 // color index for chart styling
            points.append(MomentumPoint(
                id: "\(entry.id)-\(intention.id)", // unique point id combining entry and intention
                date: entry.effectiveTookPlaceAt, // use effective occurrence time for plotting
                intentionId: intention.id, // intention identifier
                intentionTitle: intention.title, // intention title
                colorIndex: colorIdx, // color index for rendering
                percent: percent, // current percent complete
                timeOffsetSeconds: 0 // no offset needed when using actual occurrence times
            ))
        }
        return points // return chronologically built points
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
        ) // map intention ids to color indexes
        let sortedEntries = entries.sorted { $0.effectiveTookPlaceAt < $1.effectiveTookPlaceAt } // enforce chronological order by effective time
        var points: [MomentumPoint] = [] // accumulated chart points
        var totalsByIntention: [String: Double] = [:] // running totals for percent calculations

        for entry in sortedEntries { // walk entries chronologically
            switch entry.updateType { // update cumulative totals
            case "TOTAL":
                totalsByIntention[entry.intentionId] = entry.amount // overwrite with total
            case "INCREMENT":
                totalsByIntention[entry.intentionId] = (totalsByIntention[entry.intentionId] ?? 0) + entry.amount // add increment
            default:
                break // ignore unknown types
            }
            guard let intention = intentions.first(where: { $0.id == entry.intentionId }), // look up intention metadata
                  intention.targetValue > 0 else { continue } // skip if target missing
            let total = totalsByIntention[entry.intentionId] ?? 0 // current cumulative total
            let effectiveTarget: Double // denominator for percent
            if intention.timeframe.lowercased() == "weekly" { // weekly intentions convert to daily target
                effectiveTarget = intention.targetValue / 7.0 // daily target for weekly
            } else {
                effectiveTarget = intention.targetValue // daily target for non-weekly
            }
            let percent = (total / effectiveTarget) * 100.0 // compute percent complete
            let colorIdx = intentionIndexById[intention.id] ?? 0 // color index for rendering
            points.append(MomentumPoint(
                id: "\(entry.id)-\(intention.id)", // unique point id for entry-intention pair
                date: entry.effectiveTookPlaceAt, // use effective occurrence time for plotting
                intentionId: intention.id, // intention identifier
                intentionTitle: intention.title, // intention title
                colorIndex: colorIdx, // color index for chart
                percent: percent, // percent complete
                timeOffsetSeconds: 0 // no offset because actual times already separate points
            ))
        }
        return points // return chronologically built points
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
