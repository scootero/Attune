//
//  CheckInDetailView.swift
//  Attune
//
//  Detail view for a single check-in. Shows timestamp, transcript,
//  extracted progress updates, and optional mood (from stored data only).
//

import SwiftUI

struct CheckInDetailView: View {
    let checkInId: String
    
    /// Loaded check-in (nil until loaded or if not found)
    @State private var checkIn: CheckIn?
    /// Progress entries whose sourceCheckInId matches this check-in
    @State private var progressEntries: [ProgressEntry] = []
    /// All progress entries for the check-in's date (same intention set) — used for cumulative percent
    @State private var dayEntries: [ProgressEntry] = []
    /// Mood for this check-in's date (shown only if sourceCheckInId matches)
    @State private var mood: DailyMood?
    
    var body: some View {
        Group {
            if let checkIn = checkIn {
                detailContent(checkIn: checkIn)
            } else {
                notFoundView
            }
        }
        .navigationTitle("Check-in")
        .onAppear {
            loadData()
        }
    }
    
    /// Content when check-in is loaded
    private func detailContent(checkIn: CheckIn) -> some View {
        List {
            // Timestamp
            Section {
                LabeledContent("Time", value: formatDateTime(checkIn.createdAt))
            }
            
            // Full transcript
            Section("Transcript") {
                Text(checkIn.transcript)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Extracted progress updates
            if !progressEntries.isEmpty {
                let dateKey = ProgressCalculator.dateKey(for: checkIn.createdAt)
                Section("Progress Updates") {
                    ForEach(progressEntries) { entry in
                        progressEntryRow(entry, dayEntries: dayEntries, dateKey: dateKey)
                    }
                }
            }
            
            // Optional mood (only if this check-in contributed it). Slice A: score is 0-10.
            if let mood = mood, mood.sourceCheckInId == checkInId {
                Section("Mood") {
                    HStack {
                        if let label = mood.moodLabel, !label.isEmpty {
                            Text(label)
                        }
                        if let score = mood.moodScore {
                            Text("(\(score)/10)")
                                .foregroundColor(.secondary)
                        }
                        if mood.moodLabel == nil && mood.moodScore == nil {
                            Text("No mood extracted")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
    
    /// Single progress entry row with intention title, increment, and optional percentage lines (INCREMENT only).
    /// - Parameters:
    ///   - entry: The progress entry to display
    ///   - dayEntries: All entries for this check-in's date (for cumulative sum)
    ///   - dateKey: YYYY-MM-DD for the day
    private func progressEntryRow(_ entry: ProgressEntry, dayEntries: [ProgressEntry], dateKey: String) -> some View {
        let intention = IntentionStore.shared.loadIntention(id: entry.intentionId)
        let title = intention?.title ?? "Intention"
        
        // Daily goal target: weekly goals → targetValue/7, daily → targetValue (matches ProgressCalculator)
        let dailyGoalTarget: Double? = intention.map { i in
            i.timeframe.lowercased() == "weekly" ? i.targetValue / 7.0 : i.targetValue
        }
        
        // Show percentage lines only for INCREMENT when intention has a positive goal (Option 1: no TOTAL)
        let showPercentages = entry.updateType == "INCREMENT"
            && dailyGoalTarget != nil
            && (dailyGoalTarget ?? 0) > 0
        
        // This check-in's increment as % of daily goal
        let incrementPercent: Double? = showPercentages && dailyGoalTarget != nil
            ? (entry.amount / (dailyGoalTarget ?? 1)) * 100
            : nil
        // Sum of all INCREMENTs for this intention on this day, up to and including this entry
        let cumulativeAmount: Double = showPercentages
            ? ProgressCalculator.cumulativeIncrementAmountUpTo(
                entries: dayEntries,
                dateKey: dateKey,
                intentionId: entry.intentionId,
                intentionSetId: entry.intentionSetId,
                atOrBeforeCreatedAt: entry.createdAt
            )
            : 0
        // Cumulative % of daily goal, capped at 100 (per spec: do not display above 100)
        let cumulativePercent: Double? = showPercentages && dailyGoalTarget != nil && (dailyGoalTarget ?? 0) > 0
            ? min(100, (cumulativeAmount / (dailyGoalTarget ?? 1)) * 100)
            : nil
        
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            Text("\(entry.updateType): \(entry.amount) \(entry.unit)")
                .font(.caption)
                .foregroundColor(.secondary)
            // Increment % and cumulative % (INCREMENT only; hide if no goal or goal=0)
            if showPercentages, let incPct = incrementPercent, let cumPct = cumulativePercent {
                Text("\(Int(incPct))% of daily goal")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Total today: \(Int(cumPct))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            if let evidence = entry.evidence, !evidence.isEmpty {
                Text("\"\(evidence)\"")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(.vertical, 4)
    }
    
    /// View when check-in not found
    private var notFoundView: some View {
        ContentUnavailableView(
            "Check-in not found",
            systemImage: "exclamationmark.triangle",
            description: Text("This check-in may have been deleted.")
        )
    }
    
    /// Load check-in, progress entries, and mood from stores
    private func loadData() {
        checkIn = CheckInStore.shared.loadCheckIn(id: checkInId)
        guard checkIn != nil else { return }
        
        // Progress entries from this check-in
        progressEntries = ProgressStore.shared.loadAllProgressEntries()
            .filter { $0.sourceCheckInId == checkInId }
            .sorted { $0.createdAt < $1.createdAt }
        
        // Mood for this check-in's date (show only if this check-in set it)
        let dateKey = ProgressCalculator.dateKey(for: checkIn!.createdAt)
        let dailyMood = DailyMoodStore.shared.loadDailyMood(dateKey: dateKey)
        if dailyMood?.sourceCheckInId == checkInId {
            mood = dailyMood
        } else {
            mood = nil
        }
        
        // Day's entries for cumulative percent (same intention set as check-in)
        dayEntries = ProgressStore.shared.loadEntries(dateKey: dateKey, intentionSetId: checkIn!.intentionSetId)
    }
    
    /// Formats date for display
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationView {
        CheckInDetailView(checkInId: "unknown-id")
    }
}
