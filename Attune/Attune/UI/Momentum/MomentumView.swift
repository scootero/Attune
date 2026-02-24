//
//  MomentumView.swift
//  Attune
//
//  Detail page for momentum: day selector + chart of % accomplished per intention
//  at check-in times. Accessible from Home (tap card) and Library (Momentum tab).
//

import SwiftUI

/// One bar for an intention within a specific day in the week chart.
struct WeekIntentionBar: Identifiable { // Identifiable so SwiftUI ForEach can render without manual ids.
    let id = UUID() // Unique ID for stable list diffing.
    let intentionId: String // Intention identifier to align with color + legend.
    let intentionTitle: String // Human-readable intention title for legend display.
    let colorIndex: Int // Palette index for stable color assignment.
    let percent: Double // Completion percent for that intention on that day.
    let slot: Double // Horizontal slot within the day column (0.0–1.0) to spread bars (morning/midday/evening).
}

/// All bars for a single day in the week chart.
struct WeekDayChartData: Identifiable { // Identifiable so we can iterate days in the chart.
    let id = UUID() // Unique ID for list rendering.
    let date: Date // Calendar date represented by this column.
    let weekdayLetter: String // Single-letter label (M/T/W/...) shown under the column.
    let bars: [WeekIntentionBar] // Bars for each intention on this day.
}

/// Aggregate bar for a single day in the month chart.
struct MonthDayBar: Identifiable { // Identifiable for SwiftUI lists.
    let id = UUID() // Unique ID for rendering stability.
    let date: Date // Calendar date for this bar.
    let ratio: Double? // Completion ratio 0–1 (nil for future/empty days).
    let tier: MomentumTier? // Tier for coloring (nil when no data/future).
    let isFutureDay: Bool // True when the day is after today (render empty).
}

/// View mode for Momentum page tabs (day/week/month)
private enum MomentumViewMode { // Encapsulate the three display modes for clarity and type safety.
    case day // Single-day view using existing picker and chart.
    case week // Weekly view showing multiple bars per day across a week.
    case month // Monthly view showing one aggregate bar per day for the month.
}

/// Main Momentum detail page: weekday picker + chart + week/month tabs
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

    /// Current tab selection (default to day)
    @State private var viewMode: MomentumViewMode = .day // Controls which tab content is shown.

    /// Week data for week view (Mon–Sun)
    @State private var weekDaysChart: [WeekDayChartData] = [] // Holds per-day bars for the selected week.

    /// Y-axis max for week view bars
    @State private var weekYAxisMax: Double = 100 // Scales weekly bars (150 if any percent > 100).

    /// Month data for month view
    @State private var monthBars: [MonthDayBar] = [] // Holds per-day aggregate bars for the selected month.

    /// Display title for month (e.g., "Feb 2026")
    @State private var monthTitle: String = "" // Cached month label for the current month view.

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
                    
                    // Description card: explains what momentum data represents
                    HStack(alignment: .top, spacing: 12) {
                        // Icon: chart line symbol with teal accent
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 24))
                            .foregroundColor(NeonPalette.neonTeal)
                            .frame(width: 32, height: 32)
                        
                        // Description text: explains momentum tracking
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Track Your Progress")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            Text("Each bar shows how much you've accomplished for your intentions at check-in times throughout the day. Higher bars mean more progress!")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .fixedSize(horizontal: false, vertical: true) // Allow text to wrap naturally
                        }
                    }
                    .padding(16)
                    .glassCard() // Apply cyber-glass styling to match app design

                    // Mode selector: Day | Week | Month
                    modeSelector // Segmented control to switch between day/week/month views.

                    // Conditional content based on selected mode
                    switch viewMode { // Choose which section to render based on tab.
                    case .day: // Single-day view (existing behavior)
                        VStack(spacing: 12) { // Stack picker and chart for the day view.
                            WeekdayPicker(days: weekDays, selectedDate: $selectedDate) // Keep day picker for selecting a single date.
                            MomentumChartView( // Reuse the 3D chart for the selected day.
                                points: points, // Data points for the chosen day.
                                yAxisMax: yAxisMax, // Axis scaling based on day points.
                                selectedDate: selectedDate // Date for axis domain.
                            )
                        }
                    case .week: // Weekly view with multi-intention bars per day
                        VStack(spacing: 12) { // Group week controls and chart.
                            weekNavigation // Buttons to move to previous/next week.
                            MomentumWeekChartView( // New week chart showing bars per intention per day.
                                days: weekDaysChart, // Data for 7 days with per-intention bars.
                                yAxisMax: weekYAxisMax // Axis scaling for weekly bars.
                            )
                            if !weekDaysChart.isEmpty { // Only show legend when we have data.
                                weekLegend // Legend mapping intentions to colors for the week.
                            }
                        }
                    case .month: // Monthly view with aggregate bars per day
                        VStack(spacing: 12) { // Group month controls and chart.
                            monthNavigation // Buttons and title for month switching.
                            MomentumMonthChartView( // New month chart showing one bar per day.
                                bars: monthBars // Aggregate day-level bars for the month.
                            )
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Momentum")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadWeekDays() // Build weekday picker for day view on first render.
            loadPoints() // Load day-level points for the default day view.
            loadWeekData() // Preload week view data so tab switches are instant.
            loadMonthData() // Preload month view data so tab switches are instant.
        }
        .onChange(of: selectedDate) { _, _ in
            loadPoints() // Refresh day data when the selected date changes.
            loadWeekDays() // Refresh picker labels when date moves across weeks.
            loadWeekData() // Refresh week data to match new week anchor.
            loadMonthData() // Refresh month data when month anchor changes.
        }
        .onChange(of: viewMode) { _, newMode in
            switch newMode { // Respond to tab changes by ensuring data is ready.
            case .day:
                loadPoints() // Ensure day data is current when returning to Day tab.
            case .week:
                loadWeekData() // Ensure weekly data is current when switching to Week tab.
            case .month:
                loadMonthData() // Ensure monthly data is current when switching to Month tab.
            }
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

    /// Segmented control to switch between Day, Week, and Month views.
    private var modeSelector: some View {
        Picker("View Mode", selection: $viewMode) { // Use Picker for native segmented control styling.
            Text("Day") // Label for day view tab.
                .tag(MomentumViewMode.day) // Tag binds to .day case.
            Text("Week") // Label for week view tab.
                .tag(MomentumViewMode.week) // Tag binds to .week case.
            Text("Month") // Label for month view tab.
                .tag(MomentumViewMode.month) // Tag binds to .month case.
        }
        .pickerStyle(.segmented) // Render as horizontal segmented control.
    }

    /// Week navigation (prev/next) and label for the current week range.
    private var weekNavigation: some View {
        HStack {
            Button(action: { shiftSelectedDateBy(days: -7) }) { // Move back one week.
                Image(systemName: "chevron.left") // Chevron icon for previous.
                    .font(.subheadline) // Keep icon size compact.
            }
            .buttonStyle(.plain) // Plain style to match glass UI.
            Spacer() // Push title to center.
            Text(weekRangeLabel(for: selectedDate)) // Show current week range label.
                .font(.subheadline) // Subheadline size for secondary label.
                .foregroundColor(.gray) // Subtle color to avoid dominance.
            Spacer() // Balance layout for next button.
            Button(action: { shiftSelectedDateBy(days: 7) }) { // Move forward one week.
                Image(systemName: "chevron.right") // Chevron icon for next.
                    .font(.subheadline) // Compact icon size.
            }
            .buttonStyle(.plain) // Plain style to fit design.
        }
    }

    /// Month navigation (prev/next) and label for the current month.
    private var monthNavigation: some View {
        HStack {
            Button(action: { shiftMonth(by: -1) }) { // Move back one month.
                Image(systemName: "chevron.left") // Chevron for previous month.
                    .font(.subheadline) // Compact icon size.
            }
            .buttonStyle(.plain) // Plain style for consistency.
            Spacer() // Center the month title.
            Text(monthTitle.isEmpty ? monthLabel(for: selectedDate) : monthTitle) // Show cached or computed month title.
                .font(.subheadline) // Subheadline size to fit in controls row.
                .foregroundColor(.gray) // Subtle color to keep focus on chart.
            Spacer() // Balance layout.
            Button(action: { shiftMonth(by: 1) }) { // Move forward one month.
                Image(systemName: "chevron.right") // Chevron for next month.
                    .font(.subheadline) // Compact icon size.
            }
            .buttonStyle(.plain) // Plain style for consistency.
        }
    }

    /// Legend for week view: intention dot + title using MomentumPalette colors.
    private var weekLegend: some View {
        let intentions = uniqueWeekIntentions(from: weekDaysChart) // Collect unique intentions across the week.
        return ScrollView(.horizontal, showsIndicators: false) { // Allow horizontal scroll if many intentions.
            HStack(spacing: 12) { // Space dots and labels evenly.
                ForEach(intentions, id: \.id) { item in // Iterate unique intentions.
                    HStack(spacing: 6) { // Dot + label cluster.
                        Circle() // Color dot matching bar color.
                            .fill(MomentumPalette.color(forIndex: item.colorIndex)) // Use palette for color consistency.
                            .frame(width: 10, height: 10) // Compact dot size.
                        Text(item.title) // Intention title.
                            .font(.caption) // Small label size to fit.
                            .foregroundColor(.gray) // Subtle color to keep focus on chart.
                            .lineLimit(1) // Avoid wrapping.
                    }
                }
            }
            .padding(.vertical, 4) // Light padding to separate from chart.
        }
    }

    /// Shift selectedDate by a number of days (used for week navigation).
    private func shiftSelectedDateBy(days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) { // Safely compute shifted date.
            selectedDate = newDate // Update anchor date (triggers data reloads).
        }
    }

    /// Shift selectedDate by a number of months (used for month navigation).
    private func shiftMonth(by delta: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: delta, to: selectedDate) { // Compute new month anchor.
            selectedDate = newDate // Update anchor date to new month.
        }
    }

    /// Week range label (e.g., "Feb 17 – Feb 23").
    private func weekRangeLabel(for date: Date) -> String {
        let cal = Calendar.current // Calendar for date math.
        let week = MomentumPointAdapter.weekDays(containing: date) // Get Mon–Sun dates for the week.
        guard let first = week.first, let last = week.last else { return "" } // Guard against empty array.
        let formatter = DateFormatter() // Formatter for readable dates.
        formatter.dateFormat = "MMM d" // Month/day format without year.
        formatter.timeZone = TimeZone.current // Use local timezone.
        return "\(formatter.string(from: first)) – \(formatter.string(from: last))" // Compose range string.
    }

    /// Build week data for the Week tab: 7 days, bars per intention, y-axis max.
    private func loadWeekData() {
        let cal = Calendar.current // Calendar for week math.
        let week = MomentumPointAdapter.weekDays(containing: selectedDate) // Mon–Sun for current anchor date.
        guard let monday = week.first else { // Require a Monday to anchor intention set.
            weekDaysChart = [] // Clear if week cannot be determined.
            weekYAxisMax = 100 // Reset y-axis default.
            return
        }

        let dateKey = ProgressCalculator.dateKey(for: monday) // Date key for Monday.
        let sets = IntentionSetStore.shared.loadAllIntentionSets() // Load all intention sets to find active.
        guard let set = StreakCalculator.intentionSetActive(on: dateKey, from: sets) else { // Use Monday's active set.
            weekDaysChart = [] // No set means no weekly data.
            weekYAxisMax = 100 // Reset axis.
            return
        }

        let intentions = IntentionStore.shared.loadIntentions(ids: set.intentionIds) // Fetch intentions from the set.
            .filter { $0.isActive } // Only active intentions participate.
        let indexedIntentions = intentions.enumerated().map { ($0, $1) } // Pair index with intention for stable color mapping.

        var days: [WeekDayChartData] = [] // Accumulate per-day chart data.
        var maxPercent: Double = 0 // Track max percent to choose axis cap.

        for day in week { // Iterate all 7 days in the week.
            let dayKey = ProgressCalculator.dateKey(for: day) // Date key per day.
            let checkIns = CheckInStore.shared.loadCheckIns(intentionSetId: set.id, dateKey: dayKey) // Load day check-ins for the set.
            let entries = ProgressStore.shared.loadEntries(dateKey: dayKey, intentionSetId: set.id) // Load progress entries for the set on that day.

            let points = MomentumPointAdapter.buildPoints( // Build per-intention points for the day.
                dateKey: dayKey, // Current day key.
                intentionSet: set, // Use Monday's intention set for consistency.
                intentions: intentions, // Active intentions list.
                checkIns: checkIns, // Day check-ins.
                entries: entries // Day entries.
            )

            var bars: [WeekIntentionBar] = [] // Bars for this day.

            for (idx, intention) in indexedIntentions { // Iterate intentions with stable index for color.
                let matching = points.filter { $0.intentionId == intention.id } // Points for this intention.
                let lastPoint = matching.sorted(by: { $0.date < $1.date }).last // Latest point gives end-of-day percent.
                let percent = lastPoint?.percent ?? 0 // Use latest percent or zero if none.
                maxPercent = max(maxPercent, percent) // Track max for axis sizing.

                let slot = slotFor(point: lastPoint, intentionIndex: idx, totalIntentions: indexedIntentions.count, day: day) // Decide slot to spread bars horizontally.

                bars.append(WeekIntentionBar( // Build bar model for this intention/day.
                    intentionId: intention.id, // Stable ID for legend and color mapping.
                    intentionTitle: intention.title, // Title for legend use.
                    colorIndex: idx, // Color index from set order.
                    percent: percent, // Percent completion for the day.
                    slot: slot // Slot position within the day column.
                ))
            }

            let letter = weekdayLetter(for: day) // Reuse helper to label day.
            days.append(WeekDayChartData( // Append this day's chart data.
                date: day, // Calendar date for column.
                weekdayLetter: letter, // Letter label for X-axis.
                bars: bars // Per-intention bars.
            ))
        }

        weekDaysChart = days // Publish weekly data to state.
        weekYAxisMax = maxPercent > 100 ? 150 : 100 // Expand axis if any bar exceeds 100%.
    }

    /// Choose a horizontal slot for a bar within its day column based on time-of-day (or spread evenly if missing).
    private func slotFor(point: MomentumPoint?, intentionIndex: Int, totalIntentions: Int, day: Date) -> Double {
        guard let point = point else { // No point means no timestamp, so spread evenly.
            if totalIntentions <= 1 { return 0.5 } // Center when only one intention.
            let fraction = Double(intentionIndex) / Double(max(totalIntentions - 1, 1)) // Evenly space across column.
            return 0.2 + (0.6 * fraction) // Map to [0.2, 0.8] range for visual padding.
        }
        let dayStart = Calendar.current.startOfDay(for: day) // Start of the day for time ratio.
        let seconds = point.date.timeIntervalSince(dayStart) // Seconds since start.
        let ratio = seconds / 86400.0 // Normalize to 0–1 of the day.
        if ratio < 0.33 { return 0.25 } // Morning slot.
        if ratio < 0.66 { return 0.5 } // Midday slot.
        return 0.75 // Evening slot.
    }

    /// Collect unique intentions across the week to drive the legend.
    private func uniqueWeekIntentions(from days: [WeekDayChartData]) -> [(id: String, title: String, colorIndex: Int)] {
        var seen = Set<String>() // Track which intentions we've already added.
        var result: [(String, String, Int)] = [] // Accumulated legend items.
        for day in days { // Inspect each day.
            for bar in day.bars { // Inspect each bar (one per intention/day).
                if !seen.contains(bar.intentionId) { // Only add new intentions.
                    seen.insert(bar.intentionId) // Mark as seen.
                    result.append((bar.intentionId, bar.intentionTitle, bar.colorIndex)) // Store legend tuple.
                }
            }
        }
        return result // Return unique list preserving first-seen order.
    }

    /// Build month data for the Month tab: one aggregate bar per day (tier-colored).
    private func loadMonthData() {
        let cal = Calendar.current // Calendar for month math.
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: selectedDate)) else { // Compute first day of month.
            monthBars = [] // Clear if unable to determine month start.
            monthTitle = "" // Clear title.
            return
        }
        let range = cal.range(of: .day, in: .month, for: monthStart) ?? 1..<29 // Safe day count fallback as Range<Int> to match Calendar API type.
        let today = cal.startOfDay(for: Date()) // Today boundary for future detection.
        var bars: [MonthDayBar] = [] // Accumulate month bars.

        for day in range { // Iterate all days in the month.
            guard let date = cal.date(byAdding: .day, value: day - 1, to: monthStart) else { continue } // Build actual date.
            let isFuture = date > today // Flag future days.
            let dateKey = ProgressCalculator.dateKey(for: date) // Date key for data fetch.
            let sets = IntentionSetStore.shared.loadAllIntentionSets() // Load all intention sets.
            let intentionsBySet: [String: [Intention]] = sets.reduce(into: [:]) { dict, set in // Cache intentions per set.
                let list = IntentionStore.shared.loadIntentions(ids: set.intentionIds).filter { $0.isActive } // Active intentions for set.
                dict[set.id] = list // Store in map.
            }
            let set = StreakCalculator.intentionSetActive(on: dateKey, from: sets) // Active set for this date.
            guard let activeSet = set, let intentions = intentionsBySet[activeSet.id] else { // Require an active set with intentions.
                bars.append(MonthDayBar(date: date, ratio: nil, tier: nil, isFutureDay: isFuture)) // Append empty bar when no data.
                continue // Move to next day.
            }

            if isFuture { // Skip computing data for future days.
                bars.append(MonthDayBar(date: date, ratio: nil, tier: nil, isFutureDay: true)) // Future day placeholder.
                continue // Next day.
            }

            let entries = ProgressStore.shared.loadEntries(dateKey: dateKey, intentionSetId: activeSet.id) // Entries for the day.
            let overrides = OverrideStore.shared.loadOverridesForDate(dateKey: dateKey) // Overrides for the day.

            var sum: Double = 0 // Aggregate completion buckets.
            let n = max(intentions.count, 1) // Guard against divide by zero.

            for intention in intentions { // Evaluate each intention.
                let total = ProgressCalculator.totalForIntention( // Compute total progress for intention.
                    entries: entries, // Entries for the day.
                    dateKey: dateKey, // Day key.
                    intentionId: intention.id, // Intention identifier.
                    intentionSetId: activeSet.id, // Active set ID.
                    overrideAmount: overrides[intention.id] // Apply override if present.
                )
                let percent = ProgressCalculator.percentComplete( // Compute percent completion.
                    total: total, // Total progress value.
                    targetValue: intention.targetValue, // Target for intention.
                    timeframe: intention.timeframe // Timeframe (daily/weekly) for percent calc.
                )
                let value: Double // Bucketed value for tiering.
                if percent >= 1.0 { value = 1.0 } // Full completion counts as 1.
                else if percent > 0 { value = 0.5 } // Partial completion counts as 0.5.
                else { value = 0.0 } // No progress counts as 0.
                sum += value // Add to aggregate.
            }

            let ratio = sum / Double(n) // Average completion across intentions.
            let tier = tierForRatio(ratio) // Derive tier locally to color month bars.
            bars.append(MonthDayBar( // Store bar for this day.
                date: date, // Date for the bar.
                ratio: ratio, // Completion ratio.
                tier: tier, // Derived tier for color.
                isFutureDay: false // Already excluded future days here.
            ))
        }

        monthBars = bars // Publish month data.
        monthTitle = monthLabel(for: monthStart) // Cache month title for nav.
    }

    /// Format month title (e.g., "Feb 2026") for month navigation label.
    private func monthLabel(for date: Date) -> String {
        let formatter = DateFormatter() // Formatter for month labels.
        formatter.dateFormat = "MMM yyyy" // Month + year.
        formatter.timeZone = TimeZone.current // Local timezone.
        return formatter.string(from: date) // Render label.
    }

    /// Map completion ratio to momentum tier (mirrors WeekMomentumCalculator thresholds).
    private func tierForRatio(_ ratio: Double) -> MomentumTier {
        switch ratio { // Bucket ratio into tiers for consistent coloring.
        case ..<0.25: return .veryLow // 0–24%
        case 0.25..<0.5: return .low // 25–49%
        case 0.5..<0.75: return .neutral // 50–74%
        case 0.75..<1.0: return .good // 75–99%
        default: return .great // 100%+
        }
    }
}
