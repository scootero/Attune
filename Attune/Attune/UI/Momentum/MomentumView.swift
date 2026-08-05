//
//  MomentumView.swift
//  Attune
//
//  Consumer-facing progress history derived from tracked intentions and check-ins.
//

import SwiftUI

struct WeekIntentionBar: Identifiable {
    let intentionId: String
    let intentionTitle: String
    let colorIndex: Int
    let percent: Double

    var id: String { intentionId }
}

struct WeekDayChartData: Identifiable {
    let date: Date
    let weekdayLetter: String
    let bars: [WeekIntentionBar]

    var id: Date { date }
}

struct MonthDayBar: Identifiable {
    let date: Date
    let ratio: Double?
    let tier: MomentumTier?
    let isFutureDay: Bool

    var id: Date { date }
}

/// Models retained for the pre-Aug. 5 weekly chart.
struct LegacyWeekIntentionBar: Identifiable {
    let id = UUID()
    let intentionId: String
    let intentionTitle: String
    let colorIndex: Int
    let percent: Double
    let slot: Double
}

struct LegacyWeekDayChartData: Identifiable {
    let id = UUID()
    let date: Date
    let weekdayLetter: String
    let bars: [LegacyWeekIntentionBar]
}

private enum MomentumViewMode: String, CaseIterable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
}

struct MomentumView: View {
    @EnvironmentObject private var appRouter: AppRouter

    @State private var selectedDate: Date
    @State private var viewMode: MomentumViewMode = .day
    @State private var weekDays: [WeekDayItem] = []
    @State private var points: [MomentumPoint] = []
    @State private var yAxisMax: Double = 100
    @State private var weekDaysChart: [WeekDayChartData] = []
    @State private var weekYAxisMax: Double = 100
    @State private var monthBars: [MonthDayBar] = []

    @State private var legacyPoints: [MomentumPoint] = []
    @State private var legacyYAxisMax: Double = 100
    @State private var legacyWeekDaysChart: [LegacyWeekDayChartData] = []
    @State private var legacyWeekYAxisMax: Double = 100
    @State private var legacyMonthBars: [MonthDayBar] = []

    @State private var dayOverallRatio: Double = 0
    @State private var dayIntentionCount = 0
    @State private var dayCheckInCount = 0

    init(selectedDate: Date = Date()) {
        _selectedDate = State(initialValue: selectedDate)
    }

    var body: some View {
        ZStack {
            AttuneScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    modeSelector
                    periodNavigation
                    modeContent
                }
                .padding(.horizontal, AttuneTheme.horizontalPadding)
                .padding(.bottom, 112)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    MomentumHistoryView()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("Progress history")
                .accessibilityHint("Shows daily totals and progress by intention")
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear(perform: loadAllData)
        .onChange(of: selectedDate) { _, _ in loadAllData() }
        .onChange(of: viewMode) { _, _ in loadAllData() }
        .onChange(of: appRouter.momentumSelectedDate) { _, newValue in
            if let newValue {
                selectedDate = newValue
                viewMode = .day
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Momentum")
                .font(.largeTitle.bold())
                .foregroundStyle(AttuneTheme.textPrimary)

            Text("Progress recorded through your check-ins.")
                .font(.subheadline)
                .foregroundStyle(AttuneTheme.textSecondary)
        }
        .padding(.top, 8)
    }

    private var modeSelector: some View {
        Picker("Time period", selection: $viewMode) {
            ForEach(MomentumViewMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityHint("Changes the momentum chart period")
    }

    private var periodNavigation: some View {
        VStack(spacing: viewMode == .day ? 8 : 0) {
            HStack {
                periodButton(systemImage: "chevron.left", label: "Previous period") {
                    shiftPeriod(backward: true)
                }

                Spacer()

                Text(periodLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AttuneTheme.textPrimary)

                Spacer()

                periodButton(systemImage: "chevron.right", label: "Next period") {
                    shiftPeriod(backward: false)
                }
                .disabled(!canMoveForward)
                .opacity(canMoveForward ? 1 : 0.35)
            }

            if viewMode == .day {
                WeekdayPicker(days: weekDays, selectedDate: $selectedDate)
            }
        }
        .padding(12)
        .background(AttuneTheme.surface, in: RoundedRectangle(cornerRadius: AttuneTheme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AttuneTheme.controlRadius, style: .continuous)
                .stroke(AttuneTheme.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var modeContent: some View {
        switch viewMode {
        case .day:
            dayContent
        case .week:
            weekContent
        case .month:
            monthContent
        }
    }

    private var dayContent: some View {
        VStack(spacing: 14) {
            summaryCard(items: [
                SummaryItem(value: percentText(dayOverallRatio), label: "overall"),
                SummaryItem(value: "\(dayIntentionCount)", label: dayIntentionCount == 1 ? "intention" : "intentions"),
                SummaryItem(value: "\(dayCheckInCount)", label: dayCheckInCount == 1 ? "check-in" : "check-ins")
            ])

            LegacyMomentumChartView(
                points: legacyPoints,
                yAxisMax: legacyYAxisMax,
                selectedDate: selectedDate
            )

            NavigationLink {
                DayDetailView(dateKey: ProgressCalculator.dateKey(for: selectedDate))
            } label: {
                HStack {
                    Label("View daily details", systemImage: "list.bullet.rectangle")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AttuneTheme.textTertiary)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AttuneTheme.textPrimary)
                .padding(16)
            }
            .buttonStyle(.plain)
            .attuneCard()
        }
    }

    private var weekContent: some View {
        let recordedDays = weekDaysChart.filter { !$0.bars.isEmpty }.count
        let allBars = weekDaysChart.flatMap(\.bars)
        let average = allBars.isEmpty ? 0 : allBars.map(\.percent).reduce(0, +) / Double(allBars.count) / 100
        let intentionCount = Set(allBars.map(\.intentionId)).count

        return VStack(spacing: 14) {
            summaryCard(items: [
                SummaryItem(value: "\(recordedDays)", label: recordedDays == 1 ? "recorded day" : "recorded days"),
                SummaryItem(value: percentText(average), label: "avg. progress"),
                SummaryItem(value: "\(intentionCount)", label: intentionCount == 1 ? "intention" : "intentions")
            ])

            LegacyMomentumWeekChartView(days: legacyWeekDaysChart, yAxisMax: legacyWeekYAxisMax)

            if !allBars.isEmpty {
                intentionLegend(items: uniqueWeekIntentions)
            }
        }
    }

    private var monthContent: some View {
        let recorded = monthBars.compactMap(\.ratio)
        let average = recorded.isEmpty ? 0 : recorded.reduce(0, +) / Double(recorded.count)

        return VStack(spacing: 14) {
            summaryCard(items: [
                SummaryItem(value: "\(recorded.count)", label: recorded.count == 1 ? "recorded day" : "recorded days"),
                SummaryItem(value: percentText(average), label: "avg. momentum")
            ])

            LegacyMomentumMonthChartView(bars: monthBars)
        }
    }

    private struct SummaryItem {
        let value: String
        let label: String
    }

    private func summaryCard(items: [SummaryItem]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                VStack(spacing: 3) {
                    Text(item.value)
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(index == 0 ? AttuneTheme.accent : AttuneTheme.textPrimary)
                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(AttuneTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)

                if index < items.count - 1 {
                    Divider().overlay(AttuneTheme.border)
                        .frame(height: 34)
                }
            }
        }
        .padding(.vertical, 14)
        .attuneCard()
    }

    private func intentionLegend(items: [(id: String, title: String, colorIndex: Int)]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(items, id: \.id) { item in
                    Label {
                        Text(item.title).lineLimit(1)
                    } icon: {
                        Image(systemName: MomentumIdentity.symbol(forIndex: item.colorIndex))
                            .foregroundStyle(MomentumPalette.color(forIndex: item.colorIndex))
                    }
                    .font(.caption)
                    .foregroundStyle(AttuneTheme.textSecondary)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func periodButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AttuneTheme.accent)
        .accessibilityLabel(label)
    }

    private var periodLabel: String {
        switch viewMode {
        case .day:
            return selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        case .week:
            let days = MomentumPointAdapter.weekDays(containing: selectedDate)
            guard let first = days.first, let last = days.last else { return "" }
            return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            return selectedDate.formatted(.dateTime.month(.wide).year())
        }
    }

    private var canMoveForward: Bool {
        let calendar = Calendar.current
        switch viewMode {
        case .day, .week:
            let selectedWeek = MomentumPointAdapter.weekDays(containing: selectedDate)
            let currentWeek = MomentumPointAdapter.weekDays(containing: Date())
            return selectedWeek.first.map { selected in
                currentWeek.first.map { selected < $0 } ?? false
            } ?? false
        case .month:
            let selected = calendar.dateComponents([.year, .month], from: selectedDate)
            let current = calendar.dateComponents([.year, .month], from: Date())
            return (selected.year ?? 0, selected.month ?? 0) < (current.year ?? 0, current.month ?? 0)
        }
    }

    private var uniqueWeekIntentions: [(id: String, title: String, colorIndex: Int)] {
        var seen = Set<String>()
        return weekDaysChart.flatMap(\.bars).compactMap { bar in
            guard seen.insert(bar.intentionId).inserted else { return nil }
            return (bar.intentionId, bar.intentionTitle, bar.colorIndex)
        }
    }

    private func shiftPeriod(backward: Bool) {
        let amount = backward ? -1 : 1
        let component: Calendar.Component = viewMode == .month ? .month : .weekOfYear
        if let next = Calendar.current.date(byAdding: component, value: amount, to: selectedDate) {
            selectedDate = next
        }
    }

    private func percentText(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded()))%"
    }

    private func loadAllData() {
        loadWeekDays()
        loadDayData()
        loadWeekData()
        loadMonthData()
        loadLegacyDayData()
        loadLegacyWeekData()
        loadLegacyMonthData()
    }

    /// Loads the original daily chart input, including its today-only current-set fallback.
    private func loadLegacyDayData() {
        let dateKey = ProgressCalculator.dateKey(for: selectedDate)
        let sets = IntentionSetStore.shared.loadAllIntentionSets()
        var set = StreakCalculator.intentionSetActive(on: dateKey, from: sets)

        if set == nil,
           dateKey == ProgressCalculator.dateKey(for: Date()),
           let current = try? IntentionSetStore.shared.loadOrCreateCurrentIntentionSet() {
            set = current
        }

        guard let set else {
            legacyPoints = []
            legacyYAxisMax = 100
            return
        }

        let checkIns = CheckInStore.shared.loadCheckIns(intentionSetId: set.id, dateKey: dateKey)
        let entries = ProgressStore.shared.loadEntries(dateKey: dateKey, intentionSetId: set.id)
        let intentions = IntentionStore.shared.loadIntentions(ids: set.intentionIds).filter(\.isActive)
        legacyPoints = MomentumPointAdapter.buildPoints(
            dateKey: dateKey,
            intentionSet: set,
            intentions: intentions,
            checkIns: checkIns,
            entries: entries,
            overrides: OverrideStore.shared.loadOverrideRecordsForDate(dateKey: dateKey)
        )
        legacyYAxisMax = MomentumPointAdapter.yAxisMax(for: legacyPoints)
    }

    /// Recreates the original weekly data shape: every active intention gets a bar,
    /// including zero-height bars on days without a numeric progress entry.
    private func loadLegacyWeekData() {
        let days = MomentumPointAdapter.weekDays(containing: selectedDate)
        guard let monday = days.first else {
            legacyWeekDaysChart = []
            legacyWeekYAxisMax = 100
            return
        }

        let dateKey = ProgressCalculator.dateKey(for: monday)
        let sets = IntentionSetStore.shared.loadAllIntentionSets()
        guard let set = StreakCalculator.intentionSetActive(on: dateKey, from: sets) else {
            legacyWeekDaysChart = []
            legacyWeekYAxisMax = 100
            return
        }

        let intentions = IntentionStore.shared.loadIntentions(ids: set.intentionIds).filter(\.isActive)
        var maxPercent = 0.0

        legacyWeekDaysChart = days.map { day in
            let dayKey = ProgressCalculator.dateKey(for: day)
            let checkIns = CheckInStore.shared.loadCheckIns(intentionSetId: set.id, dateKey: dayKey)
            let entries = ProgressStore.shared.loadEntries(dateKey: dayKey, intentionSetId: set.id)
            let dayPoints = MomentumPointAdapter.buildPoints(
                dateKey: dayKey,
                intentionSet: set,
                intentions: intentions,
                checkIns: checkIns,
                entries: entries
            )

            let bars = intentions.enumerated().map { index, intention in
                let lastPoint = dayPoints
                    .filter { $0.intentionId == intention.id }
                    .max { $0.date < $1.date }
                let percent = lastPoint?.percent ?? 0
                maxPercent = max(maxPercent, percent)
                return LegacyWeekIntentionBar(
                    intentionId: intention.id,
                    intentionTitle: intention.title,
                    colorIndex: index,
                    percent: percent,
                    slot: legacySlot(for: lastPoint, intentionIndex: index, totalIntentions: intentions.count, day: day)
                )
            }

            return LegacyWeekDayChartData(
                date: day,
                weekdayLetter: weekdayLetter(for: day),
                bars: bars
            )
        }

        legacyWeekYAxisMax = maxPercent > 100 ? 150 : 100
    }

    private func legacySlot(
        for point: MomentumPoint?,
        intentionIndex: Int,
        totalIntentions: Int,
        day: Date
    ) -> Double {
        guard let point else {
            if totalIntentions <= 1 { return 0.5 }
            let fraction = Double(intentionIndex) / Double(max(totalIntentions - 1, 1))
            return 0.2 + (0.6 * fraction)
        }
        let seconds = point.date.timeIntervalSince(Calendar.current.startOfDay(for: day))
        let ratio = seconds / 86_400
        if ratio < 0.33 { return 0.25 }
        if ratio < 0.66 { return 0.5 }
        return 0.75
    }

    /// Recreates the original month behavior, which keeps the full calendar scaffold
    /// and calculates a zero/partial/full bucket for every non-future active day.
    private func loadLegacyMonthData() {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)),
              let range = calendar.range(of: .day, in: .month, for: monthStart) else {
            legacyMonthBars = []
            return
        }

        let today = calendar.startOfDay(for: Date())
        let sets = IntentionSetStore.shared.loadAllIntentionSets()

        legacyMonthBars = range.compactMap { day in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { return nil }
            let isFuture = date > today
            let dateKey = ProgressCalculator.dateKey(for: date)
            guard let set = StreakCalculator.intentionSetActive(on: dateKey, from: sets) else {
                return MonthDayBar(date: date, ratio: nil, tier: nil, isFutureDay: isFuture)
            }
            if isFuture {
                return MonthDayBar(date: date, ratio: nil, tier: nil, isFutureDay: true)
            }

            let intentions = IntentionStore.shared.loadIntentions(ids: set.intentionIds).filter(\.isActive)
            let entries = ProgressStore.shared.loadEntries(dateKey: dateKey, intentionSetId: set.id)
            let overrides = OverrideStore.shared.loadOverridesForDate(dateKey: dateKey)
            let count = max(intentions.count, 1)
            let score = intentions.reduce(0.0) { partial, intention in
                let total = ProgressCalculator.totalForIntention(
                    entries: entries,
                    dateKey: dateKey,
                    intentionId: intention.id,
                    intentionSetId: set.id,
                    overrideAmount: overrides[intention.id]
                )
                let percent = ProgressCalculator.percentComplete(
                    total: total,
                    targetValue: intention.targetValue,
                    timeframe: intention.timeframe
                )
                return partial + (percent >= 1 ? 1 : percent > 0 ? 0.5 : 0)
            }
            let ratio = score / Double(count)
            return MonthDayBar(date: date, ratio: ratio, tier: tier(for: ratio), isFutureDay: false)
        }
    }

    private func loadWeekDays() {
        let today = Calendar.current.startOfDay(for: Date())
        weekDays = MomentumPointAdapter.weekDays(containing: selectedDate).map { date in
            WeekDayItem(
                id: date,
                date: date,
                weekdayLetter: weekdayLetter(for: date),
                isFutureDay: date > today
            )
        }
    }

    private func loadDayData() {
        let dateKey = ProgressCalculator.dateKey(for: selectedDate)
        let detail = ProgressDataHelper.loadDayDetail(dateKey: dateKey)
        dayOverallRatio = detail.overallPercent
        dayIntentionCount = detail.intentions.count
        dayCheckInCount = detail.checkIns.count

        guard let set = detail.intentionSet else {
            points = []
            yAxisMax = 100
            return
        }

        let entries = detail.entriesByIntentionId.values.flatMap { $0 }
        points = MomentumPointAdapter.buildPoints(
            dateKey: dateKey,
            intentionSet: set,
            intentions: detail.intentions,
            checkIns: detail.checkIns,
            entries: entries,
            overrides: OverrideStore.shared.loadOverrideRecordsForDate(dateKey: dateKey)
        ).map { point in
            MomentumPoint(
                id: point.id,
                date: point.date,
                intentionId: point.intentionId,
                intentionTitle: point.intentionTitle,
                colorIndex: MomentumIdentity.index(for: point.intentionId),
                recordingId: point.recordingId,
                percent: point.percent,
                timeOffsetSeconds: point.timeOffsetSeconds
            )
        }
        yAxisMax = MomentumPointAdapter.yAxisMax(for: points)
    }

    private func loadWeekData() {
        let sets = IntentionSetStore.shared.loadAllIntentionSets()
        var maxPercent = 0.0

        weekDaysChart = MomentumPointAdapter.weekDays(containing: selectedDate).map { day in
            let dateKey = ProgressCalculator.dateKey(for: day)
            guard let set = StreakCalculator.intentionSetActive(on: dateKey, from: sets) else {
                return WeekDayChartData(date: day, weekdayLetter: weekdayLetter(for: day), bars: [])
            }

            let intentions = IntentionStore.shared.loadIntentions(ids: set.intentionIds).filter(\.isActive)
            let entries = ProgressStore.shared.loadEntries(dateKey: dateKey, intentionSetId: set.id)
            let overrides = OverrideStore.shared.loadOverridesForDate(dateKey: dateKey)

            let bars = intentions.compactMap { intention -> WeekIntentionBar? in
                let hasRecordedValue = entries.contains { $0.intentionId == intention.id } || overrides[intention.id] != nil
                guard hasRecordedValue else { return nil }
                let total = ProgressCalculator.totalForIntention(
                    entries: entries,
                    dateKey: dateKey,
                    intentionId: intention.id,
                    intentionSetId: set.id,
                    overrideAmount: overrides[intention.id]
                )
                let target = intention.timeframe.lowercased() == "weekly"
                    ? intention.targetValue / 7
                    : intention.targetValue
                let percent = target > 0 ? max(0, total / target * 100) : 0
                maxPercent = max(maxPercent, percent)
                return WeekIntentionBar(
                    intentionId: intention.id,
                    intentionTitle: intention.title,
                    colorIndex: MomentumIdentity.index(for: intention.id),
                    percent: percent
                )
            }

            return WeekDayChartData(date: day, weekdayLetter: weekdayLetter(for: day), bars: bars)
        }

        weekYAxisMax = maxPercent > 100 ? 150 : 100
    }

    private func loadMonthData() {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)),
              let range = calendar.range(of: .day, in: .month, for: monthStart) else {
            monthBars = []
            return
        }

        let today = calendar.startOfDay(for: Date())
        let sets = IntentionSetStore.shared.loadAllIntentionSets()

        monthBars = range.compactMap { day -> MonthDayBar? in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { return nil }
            let isFuture = date > today
            let dateKey = ProgressCalculator.dateKey(for: date)
            guard !isFuture,
                  let set = StreakCalculator.intentionSetActive(on: dateKey, from: sets) else {
                return MonthDayBar(date: date, ratio: nil, tier: nil, isFutureDay: isFuture)
            }

            let intentions = IntentionStore.shared.loadIntentions(ids: set.intentionIds).filter(\.isActive)
            let entries = ProgressStore.shared.loadEntries(dateKey: dateKey, intentionSetId: set.id)
            let overrides = OverrideStore.shared.loadOverridesForDate(dateKey: dateKey)
            guard !intentions.isEmpty, !entries.isEmpty || !overrides.isEmpty else {
                return MonthDayBar(date: date, ratio: nil, tier: nil, isFutureDay: false)
            }

            let totals = Dictionary(uniqueKeysWithValues: intentions.map { intention in
                let total = ProgressCalculator.totalForIntention(
                    entries: entries,
                    dateKey: dateKey,
                    intentionId: intention.id,
                    intentionSetId: set.id,
                    overrideAmount: overrides[intention.id]
                )
                return (intention.id, total)
            })
            let ratio = ProgressCalculator.overallPercentComplete(intentions: intentions, totalsByIntentionId: totals)
            return MonthDayBar(date: date, ratio: ratio, tier: tier(for: ratio), isFutureDay: false)
        }
    }

    private func weekdayLetter(for date: Date) -> String {
        let letters = ["S", "M", "T", "W", "T", "F", "S"]
        return letters[Calendar.current.component(.weekday, from: date) - 1]
    }

    private func tier(for ratio: Double) -> MomentumTier {
        switch ratio {
        case ..<0.25: return .veryLow
        case 0.25..<0.5: return .low
        case 0.5..<0.75: return .neutral
        case 0.75..<1: return .good
        default: return .great
        }
    }
}

enum MomentumIdentity {
    private static let symbols = ["circle.fill", "square.fill", "triangle.fill", "diamond.fill", "pentagon.fill", "hexagon.fill"]

    static func index(for id: String) -> Int {
        id.utf8.reduce(0) { (($0 &* 31) &+ Int($1)) % MomentumPalette.intentionColors.count }
    }

    static func symbol(forIndex index: Int) -> String {
        symbols[abs(index) % symbols.count]
    }
}
