//
//  HomeView.swift
//  Attune
//
//  Home tab: Daily Summary, Today's Progress, Record Check-In, Weekly Momentum, Streak.
//  Slice A: Layout matches design image; all data from real stores.
//

import SwiftUI

/// State of the check-in recording flow
private enum CheckInState: Equatable {
    case idle
    case requestingPermission
    case recording
    case processing
    case saved(checkInId: String)
    case error(message: String)
    case permissionDenied
    
    /// Manual Equatable implementation for enum with associated values
    /// Compares both the case and associated values for equality
    static func == (lhs: CheckInState, rhs: CheckInState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.requestingPermission, .requestingPermission):
            return true
        case (.recording, .recording):
            return true
        case (.processing, .processing):
            return true
        case (.saved(let lhsId), .saved(let rhsId)):
            return lhsId == rhsId
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.permissionDenied, .permissionDenied):
            return true
        default:
            return false
        }
    }
}

/// Highlight kind for check-in row feedback (green success, red failure)
private enum CheckInHighlightKind {
    case success
    case failure
}

/// Slice 7: Context for ambiguity disambiguation sheet (Identifiable for .sheet(item:))
private struct AmbiguitySheetData: Identifiable {
    let id = UUID()
    let ambiguousUpdates: [CheckInUpdate]
    let intentions: [Intention]
    let dateKey: String
    let intentionSetId: String
    let checkInId: String
}

/// Row data for today's progress display.
/// Identifiable so ForEach uses read-only overload (avoids Binding<[T]> overload mismatch).
private struct IntentionProgressRow: Identifiable {
    let intention: Intention
    let total: Double
    let percent: Double
    /// Used as ForEach id; matches intention.id (one row per intention)
    var id: String { intention.id }
}

struct HomeView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject var appRouter: AppRouter
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @StateObject private var checkInRecorder = CheckInRecorderService.shared
    @State private var state: CheckInState = .idle
    @State private var todaysProgress: [IntentionProgressRow] = []
    @State private var currentIntentionSet: IntentionSet?
    @State private var todayMood: DailyMood?
    @State private var streak: Int = 0
    @State private var showEditIntentions = false
    @State private var showMoodEditor = false
    @State private var showSettings = false
    /// Slice 7: Data for ambiguity disambiguation sheet (nil = not showing)
    @State private var ambiguitySheetData: AmbiguitySheetData?
    /// Today's check-ins for the Today Check-ins card (newest-first)
    @State private var todayCheckIns: [CheckIn] = []
    /// Check-in ID being processed (shows placeholder row until complete)
    @State private var processingCheckInId: String?
    /// When transcription fails: show red Failed row (cleared after highlight fades)
    @State private var failedCheckInId: String?
    @State private var failedCheckInCreatedAt: Date?
    /// Check-in ID to highlight (green success or red failure) after processing
    @State private var highlightedCheckInId: String?
    @State private var highlightKind: CheckInHighlightKind?
    /// When true, presents sheet with full Today Check-ins list
    @State private var showAllCheckInsSheet = false
    /// Slice A: Snapshot strip counts (derived from real data)
    @State private var intentionsInProgressCount: Int = 0
    @State private var intentionsCompleteCount: Int = 0
    @State private var intentionsNotStartedCount: Int = 0
    /// Slice A: Weekly momentum for Mon–Sun (current week)
    @State private var weekMomentum: WeekMomentum = WeekMomentum(days: [])
    /// Slice A: For future smart prompt (Slice B). Lowest-progress intention title or fallback.
    @State private var lowestProgressIntentionTitle: String = "What's one thing you want to move forward today?"
    /// When true, the progress card enters slider mode for manual overrides.
    @State private var isUpdateProgressMode: Bool = false // tracks whether we are showing sliders instead of bars
    /// Current slider values keyed by intention id while in update mode.
    @State private var sliderValues: [String: Double] = [:] // holds the working total for each intention while editing
    /// Original totals snapshot for cancel restore.
    @State private var originalTotals: [String: Double] = [:] // keeps baseline totals so Cancel can restore without saving
    /// Shows the subscription paywall when a free-tier limit is hit.
    @State private var showPaywall = false
    /// Optional reason text passed into the paywall sheet.
    @State private var paywallReason: String? = nil
    
    var body: some View {
        NavigationView {
        ZStack {
            AttuneScreenBackground()
            
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Text("Attune")
                            .font(.title2.bold())
                            .foregroundStyle(AttuneTheme.textPrimary)
                        Spacer()
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(AttuneTheme.textPrimary)
                                .frame(width: 44, height: 44)
                                .background(AttuneTheme.surface, in: Circle())
                                .overlay(Circle().stroke(AttuneTheme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Settings")
                        .accessibilityHint("Opens Attune settings")
                    }
                    .padding(.horizontal, AttuneTheme.horizontalPadding)
                    .padding(.top, 4)
                    
                    // Keep the primary action and today's complete status visible with minimal scrolling.
                    VStack(spacing: 8) {
                        recordCheckInCTAArea
                        todaysProgressCard
                        moodAndStreakCard
                        if subscriptionManager.canUseMomentumHistory {
                            weeklyMomentumCard
                        } else {
                            freeTodayMomentumCard
                        }
                    }
                    .padding(.horizontal, AttuneTheme.horizontalPadding)
                    .padding(.top, 6)
                    .padding(.bottom, 104)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .navigationBarHidden(true)
        .onChange(of: state) { _, newState in
            scheduleTransientStateReset(for: newState)
        }
        .onAppear {
            refreshAll()
            // Pre-create directories so they don't need to be created on button tap (reduces lag)
            try? AppPaths.ensureDirectoriesExist()
        }
        .sheet(isPresented: $showEditIntentions) {
            EditIntentionsView()
                .environmentObject(subscriptionManager)
                .onDisappear { refreshAll() }
        }
        .sheet(isPresented: $showMoodEditor) {
            MoodEditorView(dateKey: ProgressCalculator.dateKey(for: Date()), onSaved: { refreshMoodAndStreak() })
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(subscriptionManager)
        }
        .sheet(item: $ambiguitySheetData) { data in
            AmbiguityDisambiguationSheet(
                ambiguousUpdates: data.ambiguousUpdates,
                intentions: data.intentions,
                onResolve: { resolutions in
                    applyAmbiguityResolutions(resolutions, context: data)
                    ambiguitySheetData = nil
                    loadTodaysProgress()
                    refreshMoodAndStreak()
                    state = .saved(checkInId: data.checkInId)
                },
                onCancel: {
                    ambiguitySheetData = nil
                    loadTodaysProgress()
                    refreshMoodAndStreak()
                    state = .saved(checkInId: data.checkInId)
                }
            )
        }
        .sheet(isPresented: $showAllCheckInsSheet) {
            // Presents full Today Check-ins list (scrollable)
            NavigationView {
                CheckInsListView(checkIns: todayCheckIns, title: "Today Check-ins")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showAllCheckInsSheet = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(reason: paywallReason)
                .environmentObject(subscriptionManager)
        }
        }
    }
    
    // MARK: - A) Daily Summary Strip (Slice B: compact single-line)
    
    /// One compact glass row: "5 Check-ins • Mood 8/10 • 2 In Progress • 1 Done • 1 Not Started"
    /// Uses HomeStyle glassCard for modern crisp glassy look with bloom shadows.
    private var dailySummaryStrip: some View {
        Button(action: { showEditIntentions = true }) {
            Text(compactSnapshotText)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .glassCard()
    }
    
    /// Slice B: Single-line format, omit zero counts. "Done" not "Complete".
    /// Mood: shows "Mood ?" when unset (not yet from ChatGPT or manual); else "Mood X/10".
    private var compactSnapshotText: String {
        let total = intentionsInProgressCount + intentionsCompleteCount + intentionsNotStartedCount
        var parts: [String] = []
        parts.append("\(todayCheckIns.count) Check-ins")
        // When mood unset: show "Mood ?" (avoids defaulting 0 → "Stressed")
        parts.append(hasMoodSet ? "Mood \(moodScoreToday)/10" : "Mood ?")
        if total > 0 {
            if intentionsInProgressCount > 0 { parts.append("\(intentionsInProgressCount) In Progress") }
            if intentionsCompleteCount > 0 { parts.append("\(intentionsCompleteCount) Done") }
            if intentionsNotStartedCount > 0 { parts.append("\(intentionsNotStartedCount) Not Started") }
        }
        return parts.joined(separator: " • ")
    }
    
    /// True when mood has been set (from ChatGPT check-in extraction or manual MoodEditor).
    /// Used to avoid showing "Stressed" when score would default to 0.
    private var hasMoodSet: Bool {
        guard let m = todayMood else { return false }
        return m.moodLabel != nil || m.moodScore != nil
    }
    
    /// Mood score 0-10 for display (from todayMood). Only valid when hasMoodSet; else use for button default.
    private var moodScoreToday: Int {
        todayMood?.moodScore ?? 0
    }
    
    // MARK: - B) Intentions and Today's Progress
    
    private var todaysProgressCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text("Today's Intentions")
                    .font(.headline)
                    .foregroundStyle(AttuneTheme.textPrimary)
                Spacer()
                HStack(spacing: 8) {
                    if isUpdateProgressMode { // in update mode, show only update controls (hide Add/Edit)
                        pillActionButton( // cancel action pill styled with muted retro red gradient
                            title: "Cancel", // visible cancel label in the pill
                            gradient: [Color(red: 0.70, green: 0.27, blue: 0.30), Color(red: 0.62, green: 0.23, blue: 0.22)], // red-themed gradient
                            glow: Color(red: 0.85, green: 0.32, blue: 0.34), // subtle red glow color
                            action: cancelUpdateProgressMode // restore original values and exit update mode
                        )
                        pillActionButton( // save action pill styled with muted retro green gradient
                            title: "Save", // visible save label in the pill
                            gradient: [Color(red: 0.22, green: 0.60, blue: 0.42), Color(red: 0.17, green: 0.52, blue: 0.44)], // green/teal-themed gradient
                            glow: Color(red: 0.28, green: 0.74, blue: 0.54), // subtle green glow color
                            action: saveUpdateProgressMode // persist overrides and exit update mode
                        )
                    } else {
                        Button(action: { showEditIntentions = true }) {
                            Text("Manage")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AttuneTheme.accent)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Add, edit, or remove intentions")
                    }
                }
            }
            
            if todaysProgress.isEmpty {
                HStack(spacing: 10) {
                    Text("Add something you want to move forward today.")
                        .font(.subheadline)
                        .foregroundStyle(AttuneTheme.textSecondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            } else {
                ForEach(Array(todaysProgress.enumerated()), id: \.element.id) { _, row in // render each intention row
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.intention.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AttuneTheme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int(currentPercent(for: row) * 100))%")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(AttuneTheme.textPrimary)
                        }
                        
                        if isUpdateProgressMode {
                            Slider(
                                value: Binding(
                                    get: { percentForTotal(sliderValues[row.intention.id] ?? row.total, intention: row.intention) },
                                    set: { newPercent in
                                        sliderValues[row.intention.id] = totalForPercent(newPercent, intention: row.intention)
                                    }
                                ),
                                in: 0...1,
                                step: 0.01
                            )
                            .tint(AttuneTheme.accent)
                        } else {
                            SwiftUI.ProgressView(value: row.percent)
                                .tint(AttuneTheme.accent)
                                .scaleEffect(x: 1, y: 0.72, anchor: .center)
                        }

                        Text(intentionProgressSummaryText(for: row))
                            .font(.caption2)
                            .foregroundStyle(AttuneTheme.textSecondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 1)
                    .accessibilityElement(children: .combine)
                }
                
                if !isUpdateProgressMode {
                    HStack {
                        Spacer()
                        Button(action: { enterUpdateProgressMode() }) {
                            Label("Update Progress", systemImage: "slider.horizontal.3")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AttuneTheme.accent)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(AttuneTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(AttuneTheme.border)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .attuneCard()
    }

    private func intentionProgressSummaryText(for row: IntentionProgressRow) -> String {
        let currentValue = sliderValues[row.intention.id] ?? row.total
        let isWeekly = row.intention.timeframe.lowercased() == "weekly"
        let targetValue = isWeekly ? row.intention.targetValue / 7.0 : row.intention.targetValue
        let paceNote = isWeekly ? " today · weekly pace" : " today"
        return "\(formattedProgressValue(currentValue)) / \(formattedProgressValue(targetValue)) \(compactUnit(row.intention.unit))\(paceNote)"
    }

    private func compactUnit(_ unit: String) -> String {
        switch unit.lowercased() {
        case "minutes", "minute", "mins": return "min"
        default: return unit
        }
    }

    private func formattedProgressValue(_ value: Double) -> String {
        if value.rounded() == value {
            return Int(value).formatted()
        }
        return value.formatted(.number.precision(.fractionLength(1)))
    }
    
    // MARK: - B1) Smart Prompt (Slice B)
    
    /// Single line above Record button. Uses lowestProgressIntentionTitle from Slice A.
    private var smartPromptLine: some View {
        Text(smartPromptText)
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.9))
            .shadow(color: NeonPalette.neonTeal.opacity(0.2), radius: 6, x: 0, y: 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
    }
    
    private var smartPromptText: String {
        let fallback = "What's one thing you want to move forward today?"
        if lowestProgressIntentionTitle == fallback {
            return fallback
        }
        return "How's your \(lowestProgressIntentionTitle) coming along today?"
    }
    
    // MARK: - B2) Weekly Momentum Card (Slice B: lighter)
    
    /// Slice B: Bars with red→yellow→green gradient by progress; tap navigates to Library → Momentum tab.
    /// Day labels aligned on same baseline; bars bottom-aligned; slightly larger bars and text.
    private var weeklyMomentumCard: some View {
        Button(action: {
            appRouter.navigateToMomentum(date: Date())  // Jump to Library → Momentum showing today
        }) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("This Week")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AttuneTheme.textPrimary)
                    Spacer()
                    Text("View Momentum")
                        .font(.caption)
                        .foregroundStyle(AttuneTheme.accent)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AttuneTheme.accent)
                }
                
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(weekMomentum.days) { day in
                        let isToday = Calendar.current.isDateInToday(day.date)
                        VStack(spacing: 3) {
                            if day.isFutureDay {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.clear)
                                    .frame(width: 10, height: 24)
                            } else if !day.hasData {
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(AttuneTheme.surfaceStrong)
                                        .frame(width: 10, height: 6)
                                }
                                .frame(width: 10, height: 24)
                            } else {
                                let ratio = day.completionRatio ?? 0
                                let barHeight = max(6, CGFloat(ratio) * 24)
                                let barColor = colorForProgressRatio(ratio)
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(barColor)
                                        .blur(radius: 3)
                                        .opacity(0.35)
                                        .frame(width: 10, height: barHeight)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(barColor)
                                        .frame(width: 10, height: barHeight)
                                }
                                .frame(width: 10, height: 24)
                            }
                            Text(day.weekdayLetter)
                                .font(.caption2.weight(isToday ? .bold : .medium))
                                .foregroundStyle(isToday ? AttuneTheme.accent : AttuneTheme.textSecondary)
                                .frame(width: 12, alignment: .center)
                        }
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isToday ? AttuneTheme.accent.opacity(0.12) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(isToday ? AttuneTheme.accent.opacity(0.75) : Color.clear, lineWidth: 1)
                        )
                        .accessibilityLabel("\(isToday ? "Today, " : "")\(day.weekdayLetter), \(momentumAccessibilityText(for: day))")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .attuneCard()
    }

    /// Free shows only today's aggregate, matching the today-only Momentum tab.
    private var freeTodayMomentumCard: some View {
        Button {
            appRouter.navigateToMomentum(date: Date())
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                    .foregroundStyle(AttuneTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(AttuneTheme.accent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's Momentum")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AttuneTheme.textPrimary)
                    Text("\(todayMomentumPercent)% overall today")
                        .font(.caption)
                        .foregroundStyle(AttuneTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AttuneTheme.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .attuneCard()
    }

    private var todayMomentumPercent: Int {
        guard !todaysProgress.isEmpty else { return 0 }
        let average = todaysProgress.map { min(1, max(0, currentPercent(for: $0))) }.reduce(0, +) / Double(todaysProgress.count)
        return Int((average * 100).rounded())
    }
    
    /// Bar color by progress ratio: 0%=red glow, partial=yellow, 80%+=green, 100%=bright green.
    private func colorForProgressRatio(_ ratio: Double) -> Color {
        let red = Color(red: 0.95, green: 0.25, blue: 0.2)
        let orange = Color(red: 0.95, green: 0.5, blue: 0.2)
        let yellow = Color(red: 0.95, green: 0.75, blue: 0.2)
        let yellowGreen = Color(red: 0.5, green: 0.8, blue: 0.3)
        let green = Color(red: 0.2, green: 0.9, blue: 0.4)
        let superGreen = Color(red: 0.15, green: 0.95, blue: 0.5)

        switch ratio {
        case 0: return red
        case ..<0.25:
            return red.mix(with: orange, by: ratio / 0.25)
        case 0.25..<0.5:
            return orange.mix(with: yellow, by: (ratio - 0.25) / 0.25)
        case 0.5..<0.8:
            return yellow.mix(with: yellowGreen, by: (ratio - 0.5) / 0.3)
        case 0.8..<1.0:
            return yellowGreen.mix(with: green, by: (ratio - 0.8) / 0.2)
        default:
            return superGreen
        }
    }
    
    /// Enters slider-based update progress mode, initializing slider state.
    private func enterUpdateProgressMode() {
        originalTotals = Dictionary(uniqueKeysWithValues: todaysProgress.map { ($0.intention.id, $0.total) }) // snapshot current totals for cancel
        sliderValues = originalTotals // seed sliders with current totals
        isUpdateProgressMode = true // toggle mode on
    }
    
    /// Cancels update mode and restores original displayed totals without saving.
    private func cancelUpdateProgressMode() {
        sliderValues = originalTotals // restore slider values
        isUpdateProgressMode = false // exit mode
        loadTodaysProgress() // refresh to ensure UI reflects persisted state
        loadIntentionsBreakdown() // recompute counts from live data
    }
    
    /// Saves overrides for each intention based on slider values, then exits mode.
    private func saveUpdateProgressMode() {
        guard currentIntentionSet != nil else { // ensure we have a set
            isUpdateProgressMode = false // bail out to safe state
            return // nothing to save
        }
        let dateKey = ProgressCalculator.dateKey(for: Date()) // today’s date key
        for row in todaysProgress { // iterate intentions shown
            let value = sliderValues[row.intention.id] ?? row.total // use slider or existing total
            let override = ManualProgressOverride( // build override payload
                dateKey: dateKey, // apply to today
                intentionId: row.intention.id, // target intention
                amount: value, // slider total
                unit: row.intention.unit // preserve unit for display
            )
            try? OverrideStore.shared.setOverride(override) // persist override; silent fail to avoid blocking UI
        }
        isUpdateProgressMode = false // exit mode
        loadTodaysProgress() // refresh data to reflect overrides
        loadIntentionsBreakdown() // recompute counts
    }
    
    /// Computes current percent for a row using live or slider value.
    private func currentPercent(for row: IntentionProgressRow) -> Double {
        let value = sliderValues[row.intention.id] ?? row.total // choose slider or stored total
        return ProgressCalculator.percentComplete( // compute percent with existing logic
            total: value, // current value
            targetValue: row.intention.targetValue, // intention target
            timeframe: row.intention.timeframe // daily/weekly
        )
    }
    
    /// Unit-aware slider step for smoother control.
    private func sliderStep(for intention: Intention) -> Double {
        switch intention.unit.lowercased() { // unit switch
        case "minutes": return 5 // 5-minute steps
        case "pages": return 1 // per page
        case "steps": return 500 // per 500 steps
        default: return 1 // general fallback
        }
    }
    
    /// Unit-aware slider upper bound with sensible caps; always at least current total.
    private func sliderUpperBound(for intention: Intention, currentTotal: Double) -> Double {
        let unit = intention.unit.lowercased()
        let target = intention.targetValue
        let baseCap: Double
        switch unit {
        case "minutes":
            baseCap = 360 // allow up to 6 hours
        case "pages":
            baseCap = 300 // large reading session
        case "steps":
            baseCap = 50_000 // generous daily steps ceiling
        default:
            baseCap = max(100, target * 3, currentTotal * 3) // dynamic default
        }
        return max(baseCap, currentTotal) // ensure current value is always within range
    }
    
    /// Small pill-style action button for header controls with explicit size to avoid text collapsing.
    private func pillActionButton( // shared helper for Save/Cancel styling in update mode
        title: String, // label text shown inside the pill
        gradient: [Color], // gradient colors for the retro/glassy look
        glow: Color, // glow tint that matches button intent (red/green)
        action: @escaping () -> Void // action to run when button is tapped
    ) -> some View {
        Button(action: action) { // wrap label in a plain-styled button for predictable layout
            Text(title) // render visible button title text
                .font(.system(size: 14, weight: .bold, design: .rounded)) // keep text readable and compact
                .foregroundColor(.white.opacity(0.95)) // high-contrast text on colored gradient
                .lineLimit(1) // force single-line titles
                .minimumScaleFactor(0.9) // allow slight downscale instead of truncation
                .frame(minWidth: 72) // prevent narrow collapse that can look like vertical bars
                .frame(height: 36) // enforce consistent pill height
                .padding(.horizontal, 10) // horizontal breathing room around text
                .background(
                    LinearGradient( // apply red/green gradient theme for action intent
                        colors: gradient, // use caller-provided gradient palette
                        startPoint: .topLeading, // diagonal gradient start
                        endPoint: .bottomTrailing // diagonal gradient end
                    )
                )
                .clipShape(Capsule()) // maintain pill silhouette
                .overlay(
                    Capsule() // subtle border to match existing Add/Edit treatment
                        .stroke(Color.white.opacity(0.30), lineWidth: 1) // low-opacity white border
                )
                .shadow(color: glow.opacity(0.28), radius: 8, x: 0, y: 3) // subtle action-colored glow
                .fixedSize(horizontal: true, vertical: false) // keep intrinsic horizontal size for text
        }
        .buttonStyle(.plain) // avoid default button compression/tint behavior
    }
    
    /// Computes percent (0...1) from a total using existing timeframe rules.
    private func percentForTotal(_ total: Double, intention: Intention) -> Double {
        let effectiveTarget = intention.timeframe.lowercased() == "weekly"
            ? intention.targetValue / 7.0
            : intention.targetValue
        guard effectiveTarget > 0 else { return 0 }
        return min(1.0, max(0.0, total / effectiveTarget))
    }
    
    /// Computes total from a percent (0...1) using existing timeframe rules.
    private func totalForPercent(_ percent: Double, intention: Intention) -> Double {
        let clamped = min(1.0, max(0.0, percent))
        let effectiveTarget = intention.timeframe.lowercased() == "weekly"
            ? intention.targetValue / 7.0
            : intention.targetValue
        return max(0, clamped * effectiveTarget)
    }
    
    /// Displays numeric value without trailing decimals when possible.
    private func displayValue(_ value: Double) -> String {
        if value.rounded() == value { // integer check
            return String(Int(value)) // int display
        }
        return String(format: "%.1f", value) // one decimal for readability
    }
    
    // MARK: - C) Mood and streak

    private var moodAndStreakCard: some View {
        HStack(spacing: 0) {
            Button(action: { showMoodEditor = true }) {
                HStack(spacing: 10) {
                    Text(moodEmoji)
                        .font(.system(size: 27))
                        .frame(width: 38, height: 38)
                        .background(AttuneTheme.accent.opacity(0.14), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mood")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AttuneTheme.textPrimary)
                        Text(compactMoodSummaryText)
                            .font(.caption)
                            .foregroundStyle(AttuneTheme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hasMoodSet ? "Mood \(moodScoreToday) out of 10, \(moodSummaryText)" : "Set today's mood")

            Rectangle()
                .fill(AttuneTheme.border)
                .frame(width: 1, height: 40)

            HStack(spacing: 9) {
                Image(systemName: "flame.fill")
                    .font(.title3)
                    .foregroundStyle(AttuneTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(AttuneTheme.accent.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Streak")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AttuneTheme.textPrimary)
                    Text("\(streak) \(streak == 1 ? "day" : "days")")
                        .font(.caption)
                        .foregroundStyle(AttuneTheme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        .attuneCard()
    }

    private var moodEmoji: String {
        guard hasMoodSet else { return "🙂" }
        switch moodScoreToday {
        case 0...2: return "😞"
        case 3...4: return "🙁"
        case 5...6: return "😐"
        case 7...8: return "🙂"
        default: return "😄"
        }
    }

    private var compactMoodSummaryText: String {
        guard hasMoodSet else { return "Not set" }
        if let label = todayMood?.moodLabel, !label.isEmpty {
            return "\(moodScoreToday)/10 · \(label)"
        }
        return "\(moodScoreToday)/10 · \(MoodTier.moodLabel(for: MoodTier.moodTier(for: moodScoreToday)))"
    }

    private var moodSummaryText: String {
        guard hasMoodSet else { return "Add a score and optional feeling" }
        if let label = todayMood?.moodLabel, !label.isEmpty {
            return "\(label) · \(moodScoreToday)/10"
        }
        return "\(MoodTier.moodLabel(for: MoodTier.moodTier(for: moodScoreToday))) · \(moodScoreToday)/10"
    }

    // MARK: - D) Record Check-In Hero

    private var recordCheckInCTAArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick Check-In")
                .font(.headline)
                .foregroundStyle(AttuneTheme.textPrimary)

            switch state {
            case .idle:
                recordCheckInSection
            case .requestingPermission:
                statusPanel(
                    icon: "mic.badge.plus",
                    title: "Getting ready…",
                    detail: "Waiting for microphone and speech access.",
                    color: AttuneTheme.accent,
                    showsProgress: true
                )
            case .recording:
                recordingContent
            case .processing:
                processingContent
            case .saved(let checkInId):
                savedContent(checkInId: checkInId)
            case .error(let message):
                errorContent(message: message)
            case .permissionDenied:
                permissionDeniedContent
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .attuneCard()
    }

    private var recordCheckInSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Update progress or mood by voice")
                .foregroundStyle(AttuneTheme.textSecondary)
                .font(.subheadline)

            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                startCheckIn()
            }) {
                Label("Record Check-In", systemImage: "mic.fill")
            }
            .buttonStyle(AttunePrimaryButtonStyle())
            .accessibilityHint("Starts a short voice update for tracked intentions and mood")

            if !todayCheckIns.isEmpty {
                Button("\(todayCheckIns.count) \(todayCheckIns.count == 1 ? "check-in" : "check-ins") today") {
                    showAllCheckInsSheet = true
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AttuneTheme.accent)
            }
        }
    }

    private var checkInGuidanceText: String {
        if todaysProgress.isEmpty {
            return "Add an intention to update progress, or record how you feel."
        }
        return "Say the intention and amount, then “more” or “total today.” Mood is optional."
    }

    private var checkInExampleText: String {
        guard let row = todaysProgress.min(by: { $0.percent < $1.percent }) else {
            return "Try: “Mood 7 out of 10. I feel focused.”"
        }

        let unit = row.intention.unit
        let amount: String
        switch unit.lowercased() {
        case "minutes": amount = "15"
        case "pages": amount = "10"
        case "steps": amount = "1,000"
        case "miles": amount = "1"
        default: amount = "1"
        }
        return "Try: “\(row.intention.title): \(amount) \(unit) more. Mood 7 out of 10.”"
    }

    private func momentumAccessibilityText(for day: DayMomentum) -> String {
        if day.isFutureDay { return "future day" }
        guard day.hasData, let ratio = day.completionRatio else { return "no progress recorded" }
        return "\(Int(ratio * 100)) percent momentum"
    }

    private var recordingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(AttuneTheme.recording)
                    .frame(width: 10, height: 10)
                    .shadow(color: AttuneTheme.recording.opacity(0.7), radius: 6)
                Text("Listening")
                    .font(.headline)
                Spacer()
                Text(elapsedFormatted)
                    .font(.headline.monospacedDigit())
            }
            Text("Name the intention and amount. Say “more” or “total today.” Mood is optional.")
                .font(.subheadline)
                .foregroundStyle(AttuneTheme.textSecondary)
            Button(action: stopCheckIn) {
                Label("Finish Check-In", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(AttuneTheme.recording, in: RoundedRectangle(cornerRadius: AttuneTheme.controlRadius, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(AttuneTheme.recording.opacity(0.10), in: RoundedRectangle(cornerRadius: AttuneTheme.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AttuneTheme.controlRadius, style: .continuous).stroke(AttuneTheme.recording.opacity(0.35)))
    }

    private var elapsedFormatted: String {
        let mins = checkInRecorder.elapsedSec / 60
        let secs = checkInRecorder.elapsedSec % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private var processingContent: some View {
        statusPanel(
            icon: "sparkles",
            title: "Reviewing your check-in…",
            detail: "Attune is looking for clear progress and mood updates.",
            color: AttuneTheme.accentSecondary,
            showsProgress: true
        )
    }

    private func savedContent(checkInId: String) -> some View {
        VStack(spacing: 12) {
            statusPanel(
                icon: "checkmark.circle.fill",
                title: "Check-in saved",
                detail: checkInReceiptText(checkInId: checkInId),
                color: AttuneTheme.success
            )
            Button("Record another") { state = .idle }
                .buttonStyle(.bordered)
                .tint(AttuneTheme.accent)
        }
    }

    private func checkInReceiptText(checkInId: String) -> String {
        var changes: [String] = []
        let entries = ProgressStore.shared.loadAllProgressEntries()
            .filter { $0.sourceCheckInId == checkInId }
            .sorted { $0.createdAt < $1.createdAt }

        for entry in entries.prefix(2) {
            let title = IntentionStore.shared.loadIntention(id: entry.intentionId)?.title ?? "Progress"
            let amount = displayValue(entry.amount)
            if entry.updateType == "TOTAL" {
                changes.append("\(title): \(amount) \(entry.unit) total")
            } else {
                changes.append("\(title) +\(amount) \(entry.unit)")
            }
        }
        if entries.count > 2 {
            changes.append("+\(entries.count - 2) more")
        }

        if let checkIn = CheckInStore.shared.loadCheckIn(id: checkInId) {
            let dateKey = ProgressCalculator.dateKey(for: checkIn.createdAt)
            if let mood = DailyMoodStore.shared.loadDailyMood(dateKey: dateKey), mood.sourceCheckInId == checkInId {
                if let score = mood.moodScore {
                    changes.append("Mood \(score)/10")
                } else if let label = mood.moodLabel, !label.isEmpty {
                    changes.append("Mood: \(label)")
                }
            }
        }

        guard !changes.isEmpty else {
            return "Saved. No progress or mood changes were found."
        }
        return changes.joined(separator: " · ")
    }

    private func errorContent(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            statusPanel(
                icon: "exclamationmark.triangle.fill",
                title: "Check-in unavailable",
                detail: friendlyCheckInError(message),
                color: AttuneTheme.warning
            )
            HStack {
                Text("This message closes automatically.")
                    .font(.caption2)
                    .foregroundStyle(AttuneTheme.textTertiary)
                Spacer()
                Button("Try Again") { state = .idle }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(AttuneTheme.accent)
            }
        }
    }

    private var permissionDeniedContent: some View {
        VStack(spacing: 12) {
            statusPanel(
                icon: "mic.slash.fill",
                title: "Recording access is off",
                detail: "Allow Microphone and Speech Recognition in Settings to record check-ins.",
                color: AttuneTheme.warning
            )
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(AttunePrimaryButtonStyle())
            Button("Not now") { state = .idle }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AttuneTheme.textSecondary)
        }
    }

    private func statusPanel(
        icon: String,
        title: String,
        detail: String,
        color: Color,
        showsProgress: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.16))
                    .frame(width: 34, height: 34)
                if showsProgress {
                    SwiftUI.ProgressView()
                        .tint(color)
                } else {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AttuneTheme.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AttuneTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: AttuneTheme.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AttuneTheme.controlRadius, style: .continuous).stroke(color.opacity(0.26)))
    }

    private func friendlyCheckInError(_ message: String) -> String {
        let lowercased = message.lowercased()
        if lowercased.contains("permission") || lowercased.contains("denied") {
            return "Check recording permissions and try again."
        }
        if lowercased.contains("speech") || lowercased.contains("recognition") || lowercased.contains("recognizer") {
            return "Speech recognition is unavailable. Try again shortly."
        }
        if lowercased.contains("network") || lowercased.contains("internet") || lowercased.contains("offline") {
            return "Check your connection. Your recording remains on this device so you can try again."
        }
        return "Your recording couldn't be processed. Please try again."
    }

    private func scheduleTransientStateReset(for newState: CheckInState) {
        let delay: UInt64
        switch newState {
        case .saved:
            delay = 5_000_000_000
        case .error:
            delay = 8_000_000_000
        default:
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard state == newState else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                state = .idle
            }
        }
    }
    
    // MARK: - E) Streak (Slice A)
    
    private var streakSection: some View {
        HStack {
            Text("Streak Counter")
                .font(.caption)
                .foregroundColor(.gray)
            Spacer()
            Text("\(streak) days")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Data Loading
    
    private func refreshAll() {
        loadTodaysProgress()
        loadCurrentIntentionSet()
        loadTodayCheckIns()
        refreshMoodAndStreak()
        loadIntentionsBreakdown()
        loadWeekMomentum()
        loadLowestProgressIntention()
    }
    
    private func refreshMoodAndStreak() {
        loadTodayMood()
        loadStreak()
    }
    
    private func loadCurrentIntentionSet() {
        currentIntentionSet = try? IntentionSetStore.shared.loadOrCreateCurrentIntentionSet()
    }
    
    /// Loads today's check-ins (local timezone, newest-first).
    private func loadTodayCheckIns() {
        let todayKey = ProgressCalculator.dateKey(for: Date())
        let all = CheckInStore.shared.loadAllCheckIns()
        todayCheckIns = all.filter { ProgressCalculator.dateKey(for: $0.createdAt) == todayKey }
    }
    
    /// Clears highlight and failed row state after ~2 seconds
    private func scheduleClearHighlight() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            highlightedCheckInId = nil
            highlightKind = nil
            failedCheckInId = nil
            failedCheckInCreatedAt = nil
        }
    }
    
    private func loadTodayMood() {
        let dateKey = ProgressCalculator.dateKey(for: Date())
        todayMood = DailyMoodStore.shared.loadDailyMood(dateKey: dateKey)
    }
    
    private func loadTodaysProgress() {
        guard let intentionSet = try? IntentionSetStore.shared.loadOrCreateCurrentIntentionSet() else {
            todaysProgress = []
            return
        }
        
        let intentions = IntentionStore.shared.loadIntentions(ids: intentionSet.intentionIds)
            .filter { $0.isActive }
        
        guard !intentions.isEmpty else {
            todaysProgress = []
            return
        }
        
        let dateKey = ProgressCalculator.dateKey(for: Date())
        let entries = ProgressStore.shared.loadEntries(dateKey: dateKey, intentionSetId: intentionSet.id)
        let overrides = OverrideStore.shared.loadOverridesForDate(dateKey: dateKey)
        
        var rows: [IntentionProgressRow] = []
        for intention in intentions {
            let override = overrides[intention.id]
            let total = ProgressCalculator.totalForIntention(
                entries: entries,
                dateKey: dateKey,
                intentionId: intention.id,
                intentionSetId: intentionSet.id,
                overrideAmount: override
            )
            let percent = ProgressCalculator.percentComplete(
                total: total,
                targetValue: intention.targetValue,
                timeframe: intention.timeframe
            )
            rows.append(IntentionProgressRow(intention: intention, total: total, percent: percent))
        }
        
        todaysProgress = rows
        DailyReminderNotificationService.shared.refreshReminderForToday() // Re-evaluate today's reminder whenever progress data changes.
        
        if isUpdateProgressMode { // keep slider state in sync when data refreshes during update mode
            originalTotals = Dictionary(uniqueKeysWithValues: rows.map { ($0.intention.id, $0.total) }) // snapshot latest totals
            for row in rows { // walk rows
                sliderValues[row.intention.id] = row.total // align sliders to refreshed totals
            }
        }
    }
    
    /// Slice A: Compute intention state counts for Daily Summary (Not Started / In Progress / Complete)
    private func loadIntentionsBreakdown() {
        var inProgress = 0, complete = 0, notStarted = 0
        for row in todaysProgress { // iterate current progress rows
            let pct = currentPercent(for: row) // use current value (slider-aware)
            if pct >= 1.0 { complete += 1 } // count complete
            else if pct > 0 { inProgress += 1 } // count in-progress
            else { notStarted += 1 } // count not started
        }
        intentionsInProgressCount = inProgress
        intentionsCompleteCount = complete
        intentionsNotStartedCount = notStarted
    }
    
    /// Slice A: Compute WeekMomentum for current week (Mon–Sun)
    private func loadWeekMomentum() {
        guard let intentionSet = try? IntentionSetStore.shared.loadOrCreateCurrentIntentionSet() else {
            weekMomentum = WeekMomentum(days: [])
            return
        }
        let intentions = IntentionStore.shared.loadIntentions(ids: intentionSet.intentionIds)
            .filter { $0.isActive }
        
        weekMomentum = WeekMomentumCalculator.compute(
            today: Date(),
            intentionSet: intentionSet,
            intentions: intentions,
            entriesForDate: { ProgressStore.shared.loadEntries(dateKey: $0, intentionSetId: intentionSet.id) },
            overridesForDate: { OverrideStore.shared.loadOverridesForDate(dateKey: $0) }
        )
    }
    
    /// Slice A: Find lowest-progress intention for future smart prompt (Slice B)
    private func loadLowestProgressIntention() {
        let fallback = "What's one thing you want to move forward today?"
        guard !todaysProgress.isEmpty else {
            lowestProgressIntentionTitle = fallback
            return
        }
        let sorted = todaysProgress.sorted { a, b in
            if a.percent != b.percent { return a.percent < b.percent }
            if a.percent == 0 { return true }
            return a.percent < 1 && b.percent >= 1
        }
        lowestProgressIntentionTitle = sorted.first?.intention.title ?? fallback
    }
    
    /// Slice 7: Persists user-resolved ambiguous updates. totalToday → TOTAL, increment → INCREMENT.
    private func applyAmbiguityResolutions(_ resolutions: [AmbiguityResolution], context: AmbiguitySheetData) {
        let ambiguityCheckInCreatedAt = CheckInStore.shared.loadCheckIn(id: context.checkInId)?.createdAt ?? Date() // fallback to now if check-in missing; used for time resolution
        
        for r in resolutions { // process each user-chosen resolution
            let updateType: String
            switch r.choice {
            case .totalToday: updateType = "TOTAL"
            case .increment: updateType = "INCREMENT"
            case .skip: continue
            }
            do {
                _ = try ProgressStore.shared.appendProgressEntry(
                    dateKey: context.dateKey,
                    intentionSetId: context.intentionSetId,
                    intentionId: r.update.intentionId,
                    updateType: updateType,
                    amount: r.update.amount,
                    unit: r.update.unit,
                    confidence: r.update.clampedConfidence,
                    evidence: r.update.evidence,
                    sourceCheckInId: context.checkInId,
                    tookPlaceAt: resolveTookPlaceAt(update: r.update, checkInCreatedAt: ambiguityCheckInCreatedAt) // compute effective time using loaded check-in timestamp fallback
                )
            } catch {
                AppLogger.log(AppLogger.ERR, "Ambiguity resolve save failed id=\(AppLogger.shortId(r.update.intentionId)) error=\"\(error.localizedDescription)\"")
            }
        }
    }
    
    /// Resolves the effective occurrence Date for a progress update using local time components when explicit. // centralizes fallback behavior
    private func resolveTookPlaceAt(update: CheckInUpdate, checkInCreatedAt: Date) -> Date { // returns final Date used for ordering/plotting
        let calendar = Calendar.current // use current calendar to respect user locale/timezone
        if update.timeInterpretation == "explicit_time", // only construct explicit time when LLM marked it as such
           let localTime = update.tookPlaceLocalTime { // ensure components exist
            var components = calendar.dateComponents([.year, .month, .day], from: checkInCreatedAt) // reuse the check-in's calendar day
            components.hour = localTime.hour24 // set hour from parsed components
            components.minute = localTime.minute // set minute from parsed components
            components.second = 0 // normalize seconds to top of minute
            if let date = calendar.date(from: components) { // attempt to build Date in local zone
                return date // return explicit same-day time when available
            }
        }
        return checkInCreatedAt // fallback for just-now/unspecified or when build fails
    }
    
    /// Loads streak on background queue to avoid blocking main thread.
    /// Skips updating streak while Edit Intentions sheet is open—known SwiftUI bug
    /// where parent state updates freeze the sheet. We refresh on sheet dismiss via onDisappear.
    private func loadStreak() {
        StreakDataLoader.loadStreakInBackground { streakValue in
            // Avoid updating parent while Edit Intentions sheet is open;
            // known SwiftUI bug: parent updates freeze the sheet. We refresh on dismiss.
            if !showEditIntentions {
                streak = streakValue
            }
        }
    }
    
    // MARK: - Actions
    
    private func startCheckIn() {
        // Free users get a daily check-in cap; subscribers are unlimited.
        let todayCount = todayCheckIns.count
        guard subscriptionManager.canStartCheckIn(todayCheckInCount: todayCount) else {
            paywallReason = "You’ve reached today’s free Voice Check-In limit. Attune Pro includes unlimited check-ins."
            showPaywall = true
            return
        }

        switch PermissionsHelper.recordingPermissionState {
        case .ready:
            beginRecording()
        case .denied:
            state = .permissionDenied
        case .needsRequest:
            state = .requestingPermission
            Task { @MainActor in
                let granted = await PermissionsHelper.requestRecordingPermissions()
                guard state == .requestingPermission else { return }
                if granted {
                    beginRecording()
                } else {
                    state = .permissionDenied
                }
            }
        }
    }

    private func beginRecording() {
        do {
            // Use cached intention set (already loaded in onAppear, so this should be fast)
            // If not cached, this will load synchronously but should be rare
            guard let _ = try? IntentionSetStore.shared.loadOrCreateCurrentIntentionSet() else {
                state = .error(message: "Could not load intentions")
                return
            }
            
            // Start recording (this is the main operation that changes hardware state)
            _ = try checkInRecorder.startRecording()
            
            // Update state to recording (this triggers UI update immediately)
            state = .recording
        } catch {
            // If any error occurs, show error state
            state = .error(message: error.localizedDescription)
        }
    }
    
    private func stopCheckIn() {
        guard let result = checkInRecorder.stopRecording() else { return }
        processingCheckInId = result.checkInId
        state = .processing
        
        Task { @MainActor in
            await transcribeSaveAndExtract(checkInId: result.checkInId, audioURL: result.audioURL)
        }
    }
    
    private func transcribeSaveAndExtract(checkInId: String, audioURL: URL) async {
        let worker = TranscriptionWorker()
        
        do {
            let transcript = try await worker.transcribeFile(
                url: audioURL,
                sessionId: checkInId,
                segmentIndex: 0
            )
            
            guard let intentionSet = try? IntentionSetStore.shared.loadOrCreateCurrentIntentionSet() else {
                state = .error(message: "Could not load intention set")
                return
            }
            
            let audioFileName = "\(checkInId).m4a"
            let checkIn = CheckIn(
                id: checkInId,
                createdAt: Date(),
                intentionSetId: intentionSet.id,
                transcript: transcript,
                audioFileName: audioFileName
            )
            try CheckInStore.shared.saveCheckIn(checkIn)
            AppLogger.log(AppLogger.STORE, "CheckIn saved id=\(AppLogger.shortId(checkInId)) transcriptChars=\(transcript.count)")
            
            let intentions = IntentionStore.shared.loadIntentions(ids: intentionSet.intentionIds)
            let dateKey = ProgressCalculator.dateKey(for: checkIn.createdAt)
            let entries = ProgressStore.shared.loadEntries(dateKey: dateKey, intentionSetId: intentionSet.id)
            let overrides = OverrideStore.shared.loadOverridesForDate(dateKey: dateKey)
            
            var todaysTotals: [String: Double] = [:]
            for intention in intentions {
                let override = overrides[intention.id]
                let total = ProgressCalculator.totalForIntention(
                    entries: entries,
                    dateKey: dateKey,
                    intentionId: intention.id,
                    intentionSetId: intentionSet.id,
                    overrideAmount: override
                )
                todaysTotals[intention.id] = total
            }
            
            let result = await CheckInExtractorService.extract(
                transcript: transcript, // Send transcript text to GPT extractor
                intentions: intentions, // Provide current intentions for mapping
                todaysTotals: todaysTotals, // Supply today's totals for context
                checkInId: checkInId // Pass ID for logging/debugging
            )
            
            // Use AI updates, or fallback parser when AI fails/returns empty
            let updatesToUse: [CheckInUpdate]
            if result.updates.isEmpty {
#if DEBUG
                AppLogger.log(AppLogger.AI, "checkin_fallback_debug transcript_chars=\(transcript.count) ai_updates=0 checkin_id=\(AppLogger.shortId(checkInId))") // Debug: note when fallback triggers
#endif
                updatesToUse = CheckInFallbackParser.parseFallbackUpdates(transcript: transcript, intentions: intentions)
            } else {
                updatesToUse = result.updates
            }
            
            // Slice 7: Partition into clear (apply immediately) vs ambiguous (show prompt)
            // Fallback updates are all treated as clear (no ambiguity prompt)
            let intentionById = Dictionary(uniqueKeysWithValues: intentions.map { ($0.id, $0) })
            var clearUpdates: [CheckInUpdate] = []
            var ambiguousUpdates: [CheckInUpdate] = []
            if result.updates.isEmpty {
                clearUpdates = updatesToUse
            } else {
                for update in updatesToUse {
                    let targetValue = intentionById[update.intentionId]?.targetValue ?? 0
                    let currentTotal = todaysTotals[update.intentionId] ?? 0
                    if AmbiguityChecker.isAmbiguous(update: update, currentTotal: currentTotal, targetValue: targetValue, checkInCreatedAt: checkIn.createdAt) {
                        ambiguousUpdates.append(update)
                    } else {
                        clearUpdates.append(update)
                    }
                }
            }
            
            // Apply clear updates immediately; log count and each applied update
            AppLogger.log(AppLogger.AI, "checkin_apply parsed_updates_count=\(clearUpdates.count)")
            for update in clearUpdates { // apply non-ambiguous updates immediately
                do {
                    _ = try ProgressStore.shared.appendProgressEntry(
                        dateKey: dateKey,
                        intentionSetId: intentionSet.id,
                        intentionId: update.intentionId,
                        updateType: update.updateType,
                        amount: update.amount,
                        unit: update.unit,
                        confidence: update.clampedConfidence,
                        evidence: update.evidence,
                        sourceCheckInId: checkInId,
                        tookPlaceAt: resolveTookPlaceAt(update: update, checkInCreatedAt: checkIn.createdAt) // resolve explicit or fallback time for plotting
                    )
                    // Log applied update with new total for debugging
                    let entries = ProgressStore.shared.loadEntries(dateKey: dateKey, intentionSetId: intentionSet.id)
                    let newTotal = ProgressCalculator.totalForIntention(
                        entries: entries,
                        dateKey: dateKey,
                        intentionId: update.intentionId,
                        intentionSetId: intentionSet.id,
                        overrideAmount: overrides[update.intentionId]
                    )
                    let title = intentionById[update.intentionId]?.title ?? "?"
                    AppLogger.log(AppLogger.AI, "checkin_applied intentionId=\(AppLogger.shortId(update.intentionId)) title=\"\(title)\" delta=\(update.amount) \(update.unit) newTotal=\(newTotal)")
                } catch {
                    AppLogger.log(AppLogger.ERR, "ProgressEntry save failed id=\(AppLogger.shortId(update.intentionId)) error=\"\(error.localizedDescription)\"")
                }
            }
            
            if result.moodLabel != nil || result.moodScore != nil {
                do {
                    try DailyMoodStore.shared.setMoodFromCheckInIfNotOverridden(
                        dateKey: dateKey,
                        moodLabel: result.moodLabel,
                        moodScore: result.moodScore,
                        sourceCheckInId: checkInId
                    )
                } catch {
                    AppLogger.log(AppLogger.ERR, "DailyMood save failed dateKey=\(dateKey) error=\"\(error.localizedDescription)\"")
                }
            }

            loadTodaysProgress()
            refreshMoodAndStreak()

            // Clear processing placeholder; show real row with green flash
            processingCheckInId = nil
            loadTodayCheckIns()
            highlightedCheckInId = checkInId
            highlightKind = .success
            scheduleClearHighlight()

            // Ambiguous updates need the user's meaning before the receipt is final.
            // Keep processing behind the sheet until they resolve or skip them.
            if !ambiguousUpdates.isEmpty {
                ambiguitySheetData = AmbiguitySheetData(
                    ambiguousUpdates: ambiguousUpdates,
                    intentions: intentions,
                    dateKey: dateKey,
                    intentionSetId: intentionSet.id,
                    checkInId: checkInId
                )
            } else {
                state = .saved(checkInId: checkInId)
            }
            
        } catch {
            AppLogger.log(AppLogger.ERR, "Check-in transcription failed id=\(AppLogger.shortId(checkInId)) error=\"\(error.localizedDescription)\"")
            state = .error(message: error.localizedDescription)
            
            // Replace placeholder with failed row; red flash
            processingCheckInId = nil
            failedCheckInId = checkInId
            failedCheckInCreatedAt = Date()
            highlightedCheckInId = checkInId
            highlightKind = .failure
            scheduleClearHighlight()
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AppRouter())
}
