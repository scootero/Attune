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

    /// Initial date to show (e.g. today when navigated from Home)
    var initialDate: Date = Date()

    /// Selected day in the week picker
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
    /// Uses intention set active on that date (not just current) so past days show correct data.
    private func loadPoints() {
        let dateKey = ProgressCalculator.dateKey(for: selectedDate)
        guard let set = intentionSet(for: dateKey) else {
            points = []
            yAxisMax = 100
            return
        }
        let checkIns = CheckInStore.shared.loadCheckIns(intentionSetId: set.id, dateKey: dateKey)
        let entries = ProgressStore.shared.loadEntries(dateKey: dateKey, intentionSetId: set.id)
        let intentions = IntentionStore.shared.loadIntentions(ids: set.intentionIds)
            .filter { $0.isActive }

        points = MomentumPointAdapter.buildPoints(
            dateKey: dateKey,
            intentionSet: set,
            intentions: intentions,
            checkIns: checkIns,
            entries: entries
        )
        yAxisMax = MomentumPointAdapter.yAxisMax(for: points)
    }
}
