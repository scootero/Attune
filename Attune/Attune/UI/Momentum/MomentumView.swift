//
//  MomentumView.swift
//  Attune
//
//  Detail page for momentum: day selector + chart of % accomplished per intention
//  at check-in times. Accessible from Home (tap card) and Library (Momentum tab).
//

import SwiftUI

/// Main Momentum detail page: weekday picker + chart
struct MomentumView: View {

    @EnvironmentObject var appRouter: AppRouter // Access shared router so Momentum can react to deep links from Home

    /// Selected day in the week picker (passed from router or default to today)
    @State private var selectedDate: Date

    /// Week days (Mon–Sun) for the current week
    @State private var weekDays: [WeekDayItem] = []

    /// Momentum points for the selected day
    @State private var points: [MomentumPoint] = []

    /// Y-axis max for chart
    @State private var yAxisMax: Double = 100

    /// Intention set active on the selected date (same logic as Progress tab / DayDetail).
    private func intentionSet(for dateKey: String) -> IntentionSet? {
        let sets = IntentionSetStore.shared.loadAllIntentionSets()
        return StreakCalculator.intentionSetActive(on: dateKey, from: sets)
    }

    init(selectedDate: Date = Date()) {
        _selectedDate = State(initialValue: selectedDate)
    }

    var body: some View {
        ZStack {
            CyberBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Subtitle: selected date
                    Text(formatSubtitle(selectedDate))
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 4)

                    // Weekday picker (M T W T F S S)
                    WeekdayPicker(days: weekDays, selectedDate: $selectedDate)

                    // Chart card
                    MomentumChartView(
                        points: points,
                        yAxisMax: yAxisMax,
                        selectedDate: selectedDate
                    )
                }
                .padding(20)
            }
        }
        .navigationTitle("Momentum")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadWeekDays()
            loadPoints()
        }
        .onChange(of: selectedDate) { _, _ in
            loadPoints()
        }
        .onChange(of: appRouter.momentumSelectedDate) { _, newValue in // Respond to router-driven date changes (e.g., Home weekly card)
            if let newDate = newValue { // Safely unwrap the requested date
                selectedDate = newDate // Update selected date so UI refreshes to the requested day
            }
        }
    }

    /// Formats date for subtitle (e.g. "Tue, Feb 17")
    private func formatSubtitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    /// Builds weekDays for the picker (Mon–Sun of week containing selectedDate)
    private func loadWeekDays() {
        let today = Date()
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: today)

        let dates = MomentumPointAdapter.weekDays(containing: selectedDate)
        weekDays = dates.map { date in
            WeekDayItem(
                id: date,
                date: date,
                weekdayLetter: weekdayLetter(for: date),
                isFutureDay: date > startOfToday
            )
        }
    }

    /// Single letter for day (M T W T F S S)
    private func weekdayLetter(for date: Date) -> String {
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        let index = (weekday + 5) % 7
        return letters[index]
    }

    /// Loads momentum points for selected day from stores.
    /// Uses intention set active on that date; falls back to current set when today and active lookup fails.
    private func loadPoints() {
        let dateKey = ProgressCalculator.dateKey(for: selectedDate)
        var set = intentionSet(for: dateKey)
        
        // Fallback: if no active set found for this date but date is today, use current set (matches Home)
        if set == nil {
            let todayKey = ProgressCalculator.dateKey(for: Date())
            if dateKey == todayKey, let current = try? IntentionSetStore.shared.loadOrCreateCurrentIntentionSet() {
                set = current
            }
        }
        
        guard let set = set else {
            points = []
            yAxisMax = 100
            print("[Momentum] No intention set for dateKey=\(dateKey)")  // Debug: track when set is missing
            return
        }
        
        let checkIns = CheckInStore.shared.loadCheckIns(intentionSetId: set.id, dateKey: dateKey)
        let entries = ProgressStore.shared.loadEntries(dateKey: dateKey, intentionSetId: set.id)
        let intentions = IntentionStore.shared.loadIntentions(ids: set.intentionIds)
            .filter { $0.isActive }

        print("[Momentum] selectedDate=\(selectedDate) dateKey=\(dateKey)")  // Debug: verify date parsing
        print("[Momentum] set=\(set.id.prefix(6)) checkIns=\(checkIns.count) entries=\(entries.count) intentions=\(intentions.count)")  // Debug: counts

        points = MomentumPointAdapter.buildPoints(
            dateKey: dateKey,
            intentionSet: set,
            intentions: intentions,
            checkIns: checkIns,
            entries: entries
        )
        yAxisMax = MomentumPointAdapter.yAxisMax(for: points)
        
        let calendar = Calendar.current // Debug: calendar to derive day boundaries for logging
        let dayStart = calendar.startOfDay(for: selectedDate) // Debug: start of selected day in local time
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)?.addingTimeInterval(-1) ?? dayStart // Debug: end of selected day in local time
        let times = points.map { $0.date } // Debug: collect timestamps to find min/max
        let percents = points.map { $0.percent } // Debug: collect percents to find min/max
        let minTime = times.min() // Debug: earliest timestamp among points
        let maxTime = times.max() // Debug: latest timestamp among points
        let minPercent = percents.min() // Debug: smallest percent among points
        let maxPercent = percents.max() // Debug: largest percent among points
        let formatter = DateFormatter() // Debug: formatter for concise times in logs
        formatter.dateFormat = "HH:mm" // Debug: hour:minute format
        formatter.timeZone = TimeZone.current // Debug: local timezone to match chart domain
        let samplePoints = points.prefix(10).map { point in // Debug: limit sample to avoid log spam
            let timeString = formatter.string(from: point.date) // Debug: formatted point time
            let percentString = String(format: "%.1f", point.percent) // Debug: one decimal percent
            return "\(point.intentionTitle)@\(timeString)=\(percentString)%" // Debug: summary for a point
        }
        print("[Momentum] dayStart=\(dayStart) dayEnd=\(dayEnd) tz=\(TimeZone.current.identifier)")  // Debug: day bounds used by chart
        print("[Momentum] points built: \(points.count) minT=\(String(describing: minTime)) maxT=\(String(describing: maxTime)) minP=\(String(describing: minPercent)) maxP=\(String(describing: maxPercent))")  // Debug: range summary
        print("[Momentum] sample points: \(samplePoints)")  // Debug: small sample of points for inspection
    }
}
