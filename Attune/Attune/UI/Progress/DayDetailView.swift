//
//  DayDetailView.swift
//  Attune
//
//  Day detail with audit trail: intentions + progress entries + check-ins. Slice 6.
//

import SwiftUI

/// Slice 7: Wrapper for Adjust Total sheet (Identifiable for .sheet(item:))
private struct AdjustTotalSheetItem: Identifiable {
    let id = UUID()
    let intention: Intention
    let currentTotal: Double
}

private struct CheckInDetailRoute: Hashable {
    let checkInId: String
}

struct DayDetailView: View {
    let dateKey: String
    
    @State private var data: DayDetailData?
    @State private var expandedIntentionIds: Set<String> = []
    @State private var showMoodEditor = false
    /// Slice 7: Shows Adjust Total sheet for this intention (nil = not showing)
    @State private var adjustTotalForIntention: AdjustTotalSheetItem?
    
    var body: some View {
        Group {
            if let data = data {
                dayDetailContent(data: data)
            } else {
                SwiftUI.ProgressView()
            }
        }
        .navigationTitle(formatDate(data?.date ?? Date()))
        .onAppear {
            data = ProgressDataHelper.loadDayDetail(dateKey: dateKey)
        }
        .sheet(isPresented: $showMoodEditor) {
            MoodEditorView(dateKey: dateKey, onSaved: {
                data = ProgressDataHelper.loadDayDetail(dateKey: dateKey)
            })
        }
        .sheet(item: $adjustTotalForIntention) { item in
            AdjustTotalSheet(
                intention: item.intention,
                dateKey: dateKey,
                currentTotal: item.currentTotal,
                onSave: { newAmount in
                    let override = ManualProgressOverride(
                        dateKey: dateKey,
                        intentionId: item.intention.id,
                        amount: newAmount,
                        unit: item.intention.unit
                    )
                    try? OverrideStore.shared.setOverride(override)
                    data = ProgressDataHelper.loadDayDetail(dateKey: dateKey)
                    adjustTotalForIntention = nil
                },
                onCancel: { adjustTotalForIntention = nil }
            )
        }
    }
    
    private func dayDetailContent(data: DayDetailData) -> some View {
        List {
            // Header: Overall % + Mood
            Section {
                HStack {
                    Text("Overall")
                        .font(.headline)
                    Spacer()
                    Text("\(Int(data.overallPercent * 100))%")
                        .font(.headline.monospacedDigit())
                }
                
                Button(action: { showMoodEditor = true }) {
                    HStack {
                        Text("Mood")
                        Spacer()
                        Text(moodDisplayText(for: data.mood))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Intentions with expandable entries
            if let set = data.intentionSet, !data.intentions.isEmpty {
                Section("Intentions") {
                    ForEach(data.intentions, id: \.id) { intention in
                        intentionSection(dayData: data, intention: intention)
                    }
                }
            }
            
            // Check-ins
            Section("Check-ins") {
                if data.checkIns.isEmpty {
                    Text("No check-ins this day")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(data.checkIns) { checkIn in
                        NavigationLink(value: CheckInDetailRoute(checkInId: checkIn.id)) {
                            checkInRow(checkIn)
                        }
                    }
                }
            }
        }
        .navigationDestination(for: CheckInDetailRoute.self) { route in
            CheckInDetailView(checkInId: route.checkInId)
        }
    }
    
    /// dayData: the day's detail (parameter; avoids shadowing @State `data` so we can assign to it in closures)
    private func intentionSection(dayData: DayDetailData, intention: Intention) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                if expandedIntentionIds.contains(intention.id) {
                    expandedIntentionIds.remove(intention.id)
                } else {
                    expandedIntentionIds.insert(intention.id)
                }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(intention.title)
                            .font(.headline)
                        Text("\(Int(intention.targetValue)) \(intention.unit)/\(intention.timeframe)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(dayData.totalForIntention(intention).formatted(.number.precision(.fractionLength(1)))) / \(intention.targetValue.formatted(.number.precision(.fractionLength(0))))")
                        .font(.body)
                    Text("\(Int(dayData.percentForIntention(intention) * 100))%")
                        .font(.body.monospacedDigit())
                    Image(systemName: expandedIntentionIds.contains(intention.id) ? "chevron.down" : "chevron.right")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            
            if expandedIntentionIds.contains(intention.id) {
                let entries = dayData.entriesByIntentionId[intention.id] ?? []
                if entries.isEmpty {
                    Text("No entries")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(entries) { entry in
                        entryRow(entry: entry)
                    }
                }
                // Slice 7: Adjust total (override) and Clear override
                HStack(spacing: 12) {
                    Button("Adjust total") {
                        adjustTotalForIntention = AdjustTotalSheetItem(
                            intention: intention,
                            currentTotal: dayData.totalForIntention(intention)
                        )
                    }
                    .font(.caption)
                    if dayData.overridesByIntentionId[intention.id] != nil {
                        Button("Clear override") {
                            try? OverrideStore.shared.clearOverride(dateKey: dayData.dateKey, intentionId: intention.id)
                            // Assign to @State property; dayData param avoids shadowing so `data` here means self.data
                            data = ProgressDataHelper.loadDayDetail(dateKey: dayData.dateKey)
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func entryRow(entry: ProgressEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.createdAt, format: .dateTime.hour().minute())
                    .font(.caption)
                Text(entry.updateType)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(entry.amount.formatted(.number.precision(.fractionLength(1)))) \(entry.unit)")
                    .font(.caption)
            }
            if let evidence = entry.evidence, !evidence.isEmpty {
                Text(evidence)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            if let checkIn = data?.checkIns.first(where: { $0.id == entry.sourceCheckInId }) {
                Text("From check-in at \(checkIn.createdAt, format: .dateTime.hour().minute())")
                    .font(.caption2)
                    .foregroundColor(Color(uiColor: .tertiaryLabel))
            }
        }
        .padding(.vertical, 4)
        .padding(.leading, 12)
    }
    
    private func checkInRow(_ checkIn: CheckIn) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(checkIn.createdAt, format: .dateTime.hour().minute())
                .font(.caption)
            Text(String(checkIn.transcript.prefix(120)) + (checkIn.transcript.count > 120 ? "…" : ""))
                .font(.body)
                .lineLimit(3)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    /// Slice A: Mood display with 0-10 score. Format: "Label (7/10)" or "Set mood"
    private func moodDisplayText(for mood: DailyMood?) -> String {
        guard let mood = mood else { return "Set mood" }
        let label = mood.moodLabel ?? "Set mood"
        if let score = mood.moodScore {
            return "\(label) (\(score)/10)"
        }
        return label
    }
}
