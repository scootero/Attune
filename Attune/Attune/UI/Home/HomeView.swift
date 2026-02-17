//
//  HomeView.swift
//  Attune
//
//  Home tab: Daily Summary, Today's Progress, Record Check-In, Weekly Momentum, Streak.
//  Slice A: Layout matches design image; all data from real stores.
//

import SwiftUI

/// State of the check-in recording flow
private enum CheckInState {
    case idle
    case recording
    case processing
    case saved(transcript: String)
    case error(message: String)
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
    let transcript: String
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
    @EnvironmentObject var appRouter: AppRouter
    @StateObject private var checkInRecorder = CheckInRecorderService.shared
    @State private var state: CheckInState = .idle
    @State private var todaysProgress: [IntentionProgressRow] = []
    @State private var currentIntentionSet: IntentionSet?
    @State private var todayMood: DailyMood?
    @State private var streak: Int = 0
    @State private var showEditIntentions = false
    @State private var showMoodEditor = false
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
    
    var body: some View {
        NavigationView {
        ZStack {
            // Cyber glassy background: teal fog glows, vignette, modern crisp look
            CyberBackground()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Header: Attune + hamburger in compact full-width bar with gradient
                    HStack {
                        Text("Attune")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .shadow(color: NeonPalette.neonTeal.opacity(0.3), radius: 8, x: 0, y: 2)
                        Spacer()
                        Button(action: { showEditIntentions = true }) {
                            Image(systemName: "line.3.horizontal")
                                .font(.body)
                                .foregroundColor(.gray)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background {
                        // Compact gradient bar: dark base with subtle teal glow
                        LinearGradient(
                            colors: [
                                NeonPalette.darkBase.opacity(0.95),
                                NeonPalette.darkOverlay.opacity(0.9),
                                NeonPalette.fogTeal.opacity(0.15)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .ignoresSafeArea(edges: [.horizontal, .top])
                    
                    // Slice B: Scrollable content (more spacing for modern feel)
                    VStack(spacing: 16) {
                        dailySummaryStrip
                        todaysProgressCard
                        smartPromptLine
                        recordCheckInCTAArea
                        moodLabelRow
                        weeklyMomentumCard
                        streakSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .navigationBarHidden(true)
        .onAppear {
            refreshAll()
            // Request mic + speech permissions when Home loads (instead of on first record).
            // Only shows dialogs when status is .undetermined; already granted = no-op.
            PermissionsHelper.requestRecordingPermissionsIfNeeded()
        }
        .sheet(isPresented: $showEditIntentions) {
            EditIntentionsView()
                .onDisappear { refreshAll() }
        }
        .sheet(isPresented: $showMoodEditor) {
            MoodEditorView(dateKey: ProgressCalculator.dateKey(for: Date()), onSaved: { refreshMoodAndStreak() })
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
                    state = .saved(transcript: data.transcript)
                },
                onCancel: {
                    ambiguitySheetData = nil
                    loadTodaysProgress()
                    refreshMoodAndStreak()
                    state = .saved(transcript: data.transcript)
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
    
    // MARK: - B) Today's Progress Card (Slice B: compacted)
    
    private var todaysProgressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today's Progress")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
                Button(action: { showEditIntentions = true }) {
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            
            if todaysProgress.isEmpty {
                Text("No intentions yet. Add one to start tracking.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
                Button(action: { showEditIntentions = true }) {
                    Label("Add Intention", systemImage: "plus.circle.fill")
                }
                .font(.caption)
                .buttonStyle(.bordered)
            } else {
                ForEach(Array(todaysProgress.enumerated()), id: \.element.id) { _, row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.intention.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                            Spacer()
                            Text("\(Int(row.percent * 100))%")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .monospacedDigit()
                                .foregroundColor(.white)
                        }
                        SwiftUI.ProgressView(value: row.percent)
                            .tint(Color(red: 0.2, green: 0.8, blue: 0.7))
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(16)
        .glassCard()
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
    private var weeklyMomentumCard: some View {
        Button(action: {
            appRouter.navigateToMomentum(date: Date())  // Jump to Library → Momentum showing today
        }) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Weekly Momentum")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                HStack(spacing: 8) {
                    ForEach(weekMomentum.days) { day in
                        VStack(spacing: 6) {
                            if day.isFutureDay {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.clear)
                                    .frame(width: 8, height: 16)
                            } else {
                                let ratio = day.completionRatio ?? 0
                                let barHeight = max(6, CGFloat(ratio) * 48)
                                let barColor = colorForProgressRatio(ratio)
                                ZStack(alignment: .bottom) {
                                    // Glow layer behind filled bar (soft bloom)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(barColor)
                                        .blur(radius: 4)
                                        .opacity(0.5)
                                        .frame(width: 8, height: barHeight)
                                    // Main filled bar with shadow
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(barColor)
                                        .frame(width: 8, height: barHeight)
                                        .shadow(color: barColor.opacity(0.6), radius: 4, x: 0, y: 2)
                                }
                                .frame(width: 8, height: 48)
                            }
                            Text(day.weekdayLetter)
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 10)
                
                // Tap affordance: small chevron + faint gradient edge to communicate "tap for details"
                HStack {
                    Spacer()
                    Image(systemName: "chevron.up")
                        .font(.caption2)
                        .foregroundColor(NeonPalette.neonTeal.opacity(0.7))
                }
                .padding(.top, 4)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.clear, NeonPalette.neonTeal.opacity(0.08)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .padding(16)
            .contentShape(Rectangle())  // Make entire card area tappable (not just subviews)
        }
        .buttonStyle(.plain)
        .glassCard()
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
    
    // MARK: - C) Mood Label Row (below Record button, Slice A)
    
    /// Shows "Mood ?" when unset (not yet from ChatGPT or manual); else "Mood: [label]".
    /// Tapping opens MoodEditor. When unset, shows "Set mood" affordance next to it.
    private var moodLabelRow: some View {
        HStack(spacing: 8) {
            Button(action: { showMoodEditor = true }) {
                Text(hasMoodSet ? "Mood: \(MoodTier.moodLabel(for: MoodTier.moodTier(for: moodScoreToday)))" : "Mood ?")
                    .font(.subheadline)
                    .foregroundColor(hasMoodSet ? .gray : .gray.opacity(0.8))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            // When mood unset: show "Set mood" pill so user can tap to set it manually
            if !hasMoodSet {
                Button(action: { showMoodEditor = true }) {
                    Text("Set mood")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(NeonPalette.neonTeal)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(NeonPalette.neonTeal.opacity(0.15))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - D) Record Check-In CTA
    
    /// Single CTA area; all states rendered compactly (no layout shift). Slice B: tighter spacing.
    private var recordCheckInCTAArea: some View {
        VStack(spacing: 10) {
            // Compact banner for saved/error only (doesn't clutter when idle/recording/processing)
            switch state {
            case .saved(let transcript):
                savedBanner(transcript: transcript)
            case .error(let message):
                errorBanner(message: message)
            default:
                EmptyView()
            }
            
            // Primary CTA block (stable height across states)
            switch state {
            case .idle:
                recordCheckInSection
            case .recording:
                recordingContent
            case .processing:
                processingContent
            case .saved:
                Button(action: { state = .idle }) {
                    Text("Record Check-In")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                .buttonStyle(RecordCheckInButtonStyle())
            case .error:
                Button(action: { state = .idle }) {
                    Text("Try Again")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                .buttonStyle(RecordCheckInButtonStyle())
            }
        }
    }
    
    /// Slice B: Button/halo color driven by mood tier (Happy never red).
    private var recordButtonColor: Color {
        MoodTier.colorForMoodTier(MoodTier.moodTier(for: moodScoreToday))
    }
    
    /// Primary CTA: Record Check-In with blue gradient, light red/orange border, glow.
    private var recordCheckInSection: some View {
        Button(action: startCheckIn) {
            Text("Record Check-In")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
        .buttonStyle(RecordCheckInButtonStyle())
    }
    
    private var recordingContent: some View {
        VStack(spacing: 8) {
            Text("Recording \(elapsedFormatted)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button(action: stopCheckIn) {
                Label("Stop", systemImage: "stop.fill")
                    .font(.title2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(recordButtonColor)
        }
    }
    
    private var elapsedFormatted: String {
        let mins = checkInRecorder.elapsedSec / 60
        let secs = checkInRecorder.elapsedSec % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private var processingContent: some View {
        HStack(spacing: 12) {
            SwiftUI.ProgressView()
                .scaleEffect(0.9)
            Text("Transcribing...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    /// Compact banner for saved state (no duplicate progress, no large block)
    private func savedBanner(transcript: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.body)
            Text("Saved check-in")
                .font(.subheadline)
                .fontWeight(.medium)
            if !transcript.isEmpty {
                Text("·")
                    .foregroundColor(.secondary)
                Text(String(transcript.prefix(60)).trimmingCharacters(in: .whitespaces) + (transcript.count > 60 ? "…" : ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.green.opacity(0.12))
        .cornerRadius(8)
    }
    
    /// Compact banner for error state
    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.body)
            Text("Transcription failed")
                .font(.subheadline)
                .fontWeight(.medium)
            Text("·")
                .foregroundColor(.secondary)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(8)
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
    }
    
    /// Slice A: Compute intention state counts for Daily Summary (Not Started / In Progress / Complete)
    private func loadIntentionsBreakdown() {
        var inProgress = 0, complete = 0, notStarted = 0
        for row in todaysProgress {
            if row.percent >= 1.0 { complete += 1 }
            else if row.percent > 0 { inProgress += 1 }
            else { notStarted += 1 }
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
        for r in resolutions {
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
                    sourceCheckInId: context.checkInId
                )
            } catch {
                AppLogger.log(AppLogger.ERR, "Ambiguity resolve save failed id=\(AppLogger.shortId(r.update.intentionId)) error=\"\(error.localizedDescription)\"")
            }
        }
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
        do {
            _ = try IntentionSetStore.shared.loadOrCreateCurrentIntentionSet()
            _ = try checkInRecorder.startRecording()
            state = .recording
        } catch {
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
                transcript: transcript,
                intentions: intentions,
                todaysTotals: todaysTotals,
                checkInId: checkInId
            )
            
            // Use AI updates, or fallback parser when AI fails/returns empty
            let updatesToUse: [CheckInUpdate]
            if result.updates.isEmpty {
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
            for update in clearUpdates {
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
                        sourceCheckInId: checkInId
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
            
            // Slice 7: If any ambiguous, show disambiguation sheet; else finish
            if !ambiguousUpdates.isEmpty {
                processingCheckInId = nil
                loadTodayCheckIns()
                highlightedCheckInId = checkInId
                highlightKind = .success
                scheduleClearHighlight()
                ambiguitySheetData = AmbiguitySheetData(
                    ambiguousUpdates: ambiguousUpdates,
                    intentions: intentions,
                    dateKey: dateKey,
                    intentionSetId: intentionSet.id,
                    checkInId: checkInId,
                    transcript: transcript
                )
            } else {
                loadTodaysProgress()
                refreshMoodAndStreak()
                state = .saved(transcript: transcript)
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
            state = .saved(transcript: transcript)
            
            // Clear processing placeholder; show real row with green flash
            processingCheckInId = nil
            loadTodayCheckIns()
            highlightedCheckInId = checkInId
            highlightKind = .success
            scheduleClearHighlight()
            
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
