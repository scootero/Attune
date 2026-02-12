//
//  ProgressView.swift
//  Attune
//
//  Progress tab: Daily Totals (last 7 days) and Per Goal views. Slice 6.
//

import SwiftUI

private enum ProgressTab: String, CaseIterable {
    case dailyTotals = "Daily Totals"
    case perGoal = "Per Goal"
}

/// Route value for DayDetail
private struct DayDetailRoute: Hashable {
    let dateKey: String
}

/// Route value for IntentionDetail (uses id to look up from intentionRows)
private struct IntentionDetailRoute: Hashable {
    let intentionId: String
}

struct ProgressView: View {
    @State private var selectedTab: ProgressTab = .dailyTotals
    @State private var dayRows: [DayRow] = []
    @State private var intentionRows: [IntentionRow] = []
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $selectedTab) {
                    ForEach(ProgressTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                switch selectedTab {
                case .dailyTotals:
                    dailyTotalsContent
                case .perGoal:
                    perGoalContent
                }
            }
            .navigationTitle("Progress")
            .navigationDestination(for: DayDetailRoute.self) { route in
                DayDetailView(dateKey: route.dateKey)
            }
            .navigationDestination(for: IntentionDetailRoute.self) { route in
                IntentionDetailRouteView(intentionId: route.intentionId, intentionRows: intentionRows)
            }
            .onAppear {
                loadData()
            }
        }
    }
    
    // MARK: - Daily Totals
    
    private var dailyTotalsContent: some View {
        List {
                ForEach(dayRows) { row in
                NavigationLink(value: DayDetailRoute(dateKey: row.dateKey)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatDate(row.date))
                                .font(.headline)
                            if let mood = row.moodLabel, !mood.isEmpty {
                                Text(mood)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(Int(row.overallPercent * 100))%")
                            .font(.headline.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    // MARK: - Per Goal
    
    private var perGoalContent: some View {
        Group {
            if intentionRows.isEmpty {
                ContentUnavailableView(
                    "No intentions",
                    systemImage: "target",
                    description: Text("Add intentions on the Home tab to track progress per goal.")
                )
            } else {
                List {
                    ForEach(intentionRows) { row in
                        NavigationLink(value: IntentionDetailRoute(intentionId: row.intention.id)) {
                            HStack {
                                Text(row.intention.title)
                                    .font(.body)
                                Spacer()
                                Text("\(Int(row.intention.targetValue)) \(row.intention.unit)/\(row.intention.timeframe)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Data
    
    private func loadData() {
        dayRows = ProgressDataHelper.loadDayRows()
        intentionRows = ProgressDataHelper.loadIntentionRows()
    }
}

#Preview {
    ProgressView()
}
