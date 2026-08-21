//
//  HomeView.swift
//  Attune
//
//  Home tab: Daily Summary, Today's Progress, Record Check-In, Weekly Momentum, Streak.
//  Slice A: Layout matches design image; all data from real stores.
//

import SwiftUI
import UIKit
import StoreKit

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

/// Keep the redesigned Home chart independently reversible while it is being
/// evaluated. Change this one value to `.depthDials` or `.classicBars` to
/// restore either earlier card without touching its implementation or data.
private enum HomeWeeklyMomentumDesign {
    case dayTiles
    case depthDials
    case classicBars

    static let active: Self = .dayTiles
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

/// Prevents opening and saving the manual editor from creating chart events for
/// intentions whose totals were not actually changed.
enum ManualProgressSavePolicy {
    static func hasChanged(current: Double, original: Double, epsilon: Double = 0.000_001) -> Bool {
        abs(current - original) > epsilon
    }
}

/// Draft slider totals are visible only while the manual editor is open.
/// Once editing ends, persisted progress is always the source of truth.
enum ManualProgressDisplayPolicy {
    static func displayedTotal(stored: Double, draft: Double?, isEditing: Bool) -> Double {
        isEditing ? (draft ?? stored) : stored
    }
}

/// Keeps manual progress continuous while adding a gentle magnetic stop at
/// each eighth of the track (0%, 12.5%, ... 100%).
enum ManualProgressSliderPolicy {
    static let segmentCount = 8
    static let snapThreshold = 0.02

    static var tickPercents: [Double] {
        (0...segmentCount).map { Double($0) / Double(segmentCount) }
    }

    static func nearbyTickIndex(for percent: Double) -> Int? {
        let clamped = min(1, max(0, percent))
        let nearestIndex = Int((clamped * Double(segmentCount)).rounded())
        let nearestPercent = Double(nearestIndex) / Double(segmentCount)
        return abs(clamped - nearestPercent) <= snapThreshold ? nearestIndex : nil
    }

    static func adjustedPercent(_ percent: Double) -> Double {
        let clamped = min(1, max(0, percent))
        guard let tickIndex = nearbyTickIndex(for: clamped) else { return clamped }
        return Double(tickIndex) / Double(segmentCount)
    }
}

/// UIKit haptics are kept out of the persistence path so a disabled system
/// haptics setting never changes save behavior.
@MainActor
private enum ManualProgressHaptics {
    static func editorOpened() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.35)
    }

    static func crossedTick() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func savedChanges() {
        Task { @MainActor in
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.prepare()
            generator.impactOccurred(intensity: 0.35)
            try? await Task.sleep(for: .milliseconds(110))
            generator.prepare()
            generator.impactOccurred(intensity: 0.55)
            try? await Task.sleep(for: .milliseconds(140))
            generator.impactOccurred(intensity: 0.8)
        }
    }
}

struct HomeView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
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
    /// Tick currently holding each manual slider, used to avoid repeated haptics while it remains in one snap zone.
    @State private var activeProgressSnapTicks: [String: Int] = [:]
    /// Intention rows that recently received a visible progress change.
    @State private var highlightedProgressIntentionIDs: Set<String> = []
    /// Prevents an older delayed reset from clearing a newer progress highlight.
    @State private var progressHighlightToken = UUID()
    /// Shows the subscription paywall when a free-tier limit is hit.
    @State private var showPaywall = false
    /// Optional reason text passed into the paywall sheet.
    @State private var paywallReason: String? = nil
    @State private var intentionSuggestion: SuggestedIntentionAction?
    @State private var suggestionNudge: String?
    @State private var isGeneratingSuggestion = false
    @State private var showSuggestionEditor = false
    @State private var showSuggestionEvidence = false
    @ObservedObject private var suggestionToastCenter = IntentionSuggestionToastCenter.shared
    @State private var oneThingMode = OneThingModeState.empty
    @State private var suggestedReplacement: Intention?
    
    var body: some View {
        NavigationView {
        ZStack {
            AttuneScreenBackground()
            
            ScrollView {
                VStack(spacing: 0) {
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
                        if IntentionSuggestionFeature.isEnabled {
                            intentionSuggestionArea
                        }
                    }
                    .padding(.horizontal, AttuneTheme.horizontalPadding)
                    .padding(.top, 6)
                    .padding(.bottom, 104)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)

            if let suggestion = suggestionToastCenter.homeSuggestion {
                IntentionSuggestionToast(
                    suggestion: suggestion,
                    onReview: {
                        suggestionToastCenter.dismissHomeSuggestion(id: suggestion.id)
                        intentionSuggestion = suggestion
                        showSuggestionEditor = true
                    },
                    onDismiss: { declineSuggestion(suggestion) }
                )
                .padding(.horizontal, AttuneTheme.horizontalPadding)
                .padding(.bottom, 76)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .transition(suggestionToastTransition(edge: .bottom))
                .zIndex(4)
                .task(id: suggestion.id) {
                    await autoDismissHomeSuggestion(suggestion)
                }
            }
        }
        .navigationBarHidden(true)
        .onChange(of: state) { _, newState in
            scheduleTransientStateReset(for: newState)
        }
        .onAppear {
            refreshAll()
            // Pre-create directories so they don't need to be created on button tap (reduces lag)
            try? AppPaths.ensureDirectoriesExist()
            Task { await evaluateIntentionSuggestion() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .attuneListeningSessionDidFinishProcessing)) { _ in
            Task { await evaluateIntentionSuggestion(shouldPresentToast: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .attuneReviewIntentionSuggestion)) { notification in
            guard let suggestion = notification.object as? SuggestedIntentionAction else { return }
            intentionSuggestion = suggestion
            suggestionToastCenter.dismissHomeSuggestion(id: suggestion.id)
            showSuggestionEditor = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .attuneIntentionSuggestionDidResolve)) { notification in
            guard let suggestionId = notification.object as? String,
                  intentionSuggestion?.id == suggestionId else { return }
            intentionSuggestion = nil
        }
        .sheet(isPresented: $showEditIntentions) {
            EditIntentionsView()
                .environmentObject(subscriptionManager)
                .onDisappear { refreshAll() }
        }
        .sheet(isPresented: $showMoodEditor) {
            MoodEditorView(dateKey: ProgressCalculator.dateKey(for: Date()), onSaved: { refreshMoodAndStreak() })
        }
        .sheet(isPresented: $showSuggestionEditor, onDismiss: {
            // The editor persists synchronously, but Home can otherwise render
            // one stale frame while the sheet is being torn down.
            refreshAll()
        }) {
            if let suggestion = intentionSuggestion {
                EditIntentionsView(
                    initialAddDraft: DraftIntention(
                        id: UUID().uuidString,
                        title: suggestion.title,
                        targetValue: suggestion.targetValue,
                        unit: suggestion.unit,
                        timeframe: suggestion.timeframe
                    ),
                    onSuggestedIntentionSaved: { acceptSuggestion(suggestion) },
                    replacementIntentionId: suggestedReplacement?.id,
                    replacementIntentionTitle: suggestedReplacement?.title
                )
                .environmentObject(subscriptionManager)
            }
        }
        .sheet(isPresented: $showSuggestionEvidence) {
            if let suggestion = intentionSuggestion {
                NavigationStack {
                    List {
                        Section("Why this appeared") {
                            Text(suggestion.reason)
                            if let mentionCount = suggestion.rapidTestMentionCount {
                                Text("Rapid test mode counted \(mentionCount) related mentions at least three minutes apart.")
                            } else if let monthCount = suggestion.currentMonthSessionCount, monthCount > 0 {
                                Text("You brought up \(suggestion.topicTitle) in \(monthCount) separate Talk it out sessions this month.")
                            } else {
                                Text("You brought up \(suggestion.topicTitle) in \(suggestion.distinctSessionCount ?? Set(suggestion.evidence.map(\.sessionId)).count) separate Talk it out sessions.")
                            }
                        }
                        Section("Your words") {
                            ForEach(suggestion.evidence) { evidence in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(evidence.quote)
                                    Text(evidence.sessionDate, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if suggestion.sourceTitle != nil || suggestion.safetyNote != nil {
                            Section("General guidance") {
                                if let sourceTitle = suggestion.sourceTitle,
                                   let sourceURL = suggestion.sourceURL,
                                   let url = URL(string: sourceURL) {
                                    Link(sourceTitle, destination: url)
                                }
                                if let safetyNote = suggestion.safetyNote {
                                    Text(safetyNote)
                                }
                            }
                        }
                    }
                    .navigationTitle("Why this suggestion?")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showSuggestionEvidence = false } } }
                }
            }
        }
        .sheet(item: $ambiguitySheetData) { data in
            AmbiguityDisambiguationSheet(
                ambiguousUpdates: data.ambiguousUpdates,
                intentions: data.intentions,
                onResolve: { resolutions in
                    let previousPercents = displayedProgressPercentages()
                    applyAmbiguityResolutions(resolutions, context: data)
                    ambiguitySheetData = nil
                    refreshAll()
                    highlightProgressRows(changedProgressIntentionIDs(since: previousPercents))
                    completeCheckIn(data.checkInId)
                },
                onCancel: {
                    ambiguitySheetData = nil
                    refreshAll()
                    completeCheckIn(data.checkInId)
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

    @ViewBuilder
    private var intentionSuggestionArea: some View {
        if let suggestion = intentionSuggestion {
            VStack(alignment: .leading, spacing: 10) {
                Text("A SMALL NEXT STEP")
                    .font(.caption.weight(.bold))
                    .tracking(1.0)
                    .foregroundStyle(AttuneTheme.accent)
                Text(suggestion.title)
                    .font(.headline)
                    .foregroundStyle(AttuneTheme.textPrimary)
                Text("\(suggestion.targetValue.formatted()) \(suggestion.unit) · \(suggestion.timeframe)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AttuneTheme.textSecondary)
                Text(suggestion.reason)
                    .font(.subheadline)
                    .foregroundStyle(AttuneTheme.textSecondary)
                if let safetyNote = suggestion.safetyNote {
                    Text(safetyNote)
                        .font(.caption)
                        .foregroundStyle(AttuneTheme.textTertiary)
                }
                if let replacement = suggestedReplacement {
                    Text("Maybe let “\(replacement.title)” rest for now and try this instead. It can come off the bench later.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AttuneTheme.textSecondary)
                }
                HStack {
                    Button("Why this?") { showSuggestionEvidence = true }
                        .buttonStyle(.borderless)
                    Spacer()
                    Button("Not for me") { declineSuggestion(suggestion) }
                        .buttonStyle(.borderless)
                    Button(suggestedReplacement == nil ? "Add this" : "Review swap") { showSuggestionEditor = true }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .attuneCard()
        } else if let suggestionNudge {
            HStack(spacing: 10) {
                Image(systemName: "waveform.badge.mic")
                    .foregroundStyle(AttuneTheme.accent)
                Text(suggestionNudge)
                    .font(.subheadline)
                    .foregroundStyle(AttuneTheme.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(14)
            .attuneCard()
        } else if isGeneratingSuggestion {
            HStack(spacing: 10) {
                ProgressView()
                Text("Looking for one useful small step…")
                    .font(.subheadline)
                    .foregroundStyle(AttuneTheme.textSecondary)
            }
            .padding(14)
            .attuneCard()
        }
    }
    
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
            progressCardHeader

            if OneThingModeFeature.isEnabled && oneThingMode.isActive {
                oneThingModeBanner
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
                ForEach(Array(todaysProgress.enumerated()), id: \.element.id) { index, row in // render each intention row
                    let neonTextColor = intentionNeonTextColor(at: index)
                    let neonAccentColor = intentionNeonAccentColor(at: index)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.intention.title)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(neonTextColor)
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int(currentPercent(for: row) * 100))%")
                                .font(.headline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(neonTextColor)
                        }
                        
                        if isUpdateProgressMode {
                            manualProgressSlider(for: row, tint: neonAccentColor)
                        } else {
                            SwiftUI.ProgressView(value: row.percent)
                                .tint(neonAccentColor)
                                .scaleEffect(x: 1, y: 1.65, anchor: .center)
                                .frame(height: 10)
                                .shadow(color: neonAccentColor.opacity(0.62), radius: 4)
                        }

                        Text(intentionProgressSummaryText(for: row))
                            .font(.caption2)
                            .foregroundStyle(AttuneTheme.textSecondary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                highlightedProgressIntentionIDs.contains(row.id)
                                    ? AttuneTheme.success.opacity(0.18)
                                    : Color.clear
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                highlightedProgressIntentionIDs.contains(row.id)
                                    ? AttuneTheme.success.opacity(0.55)
                                    : Color.clear,
                                lineWidth: 1
                            )
                    )
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.45),
                        value: highlightedProgressIntentionIDs
                    )
                    .opacity(oneThingMode.isActive && oneThingMode.focusedIntentionId != row.id ? 0.38 : 1)
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
        .todayIntentionsCard()
    }

    private var oneThingModeBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("ONE THING MODE", systemImage: "lock.shield")
                .font(.caption.weight(.bold))
                .tracking(0.9)
                .foregroundStyle(AttuneTheme.warning)
            Text("Two quiet days. The juggling act is off duty—pick one thing to move.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AttuneTheme.textPrimary)
            HStack {
                Menu {
                    ForEach(todaysProgress) { row in
                        Button(row.intention.title) { selectOneThing(row.intention.id) }
                    }
                } label: {
                    Label("Switch focus", systemImage: "arrow.triangle.swap")
                }
                Spacer()
                Button("Exit") { exitOneThingMode() }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(12)
        .background(AttuneTheme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AttuneTheme.warning.opacity(0.35)))
    }

    @ViewBuilder
    private var progressCardHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                progressCardTitle
                progressCardActions
            }
        } else {
            HStack(alignment: .center) {
                progressCardTitle
                Spacer()
                progressCardActions
            }
        }
    }

    private var progressCardTitle: some View {
        Text("Today's Intentions")
            .font(.headline)
            .foregroundStyle(AttuneTheme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var progressCardActions: some View {
        HStack(spacing: 8) {
            if isUpdateProgressMode {
                pillActionButton(
                    title: "Cancel",
                    gradient: [Color(red: 0.70, green: 0.27, blue: 0.30), Color(red: 0.62, green: 0.23, blue: 0.22)],
                    glow: Color(red: 0.85, green: 0.32, blue: 0.34),
                    action: cancelUpdateProgressMode
                )
                pillActionButton(
                    title: "Save",
                    gradient: [Color(red: 0.22, green: 0.60, blue: 0.42), Color(red: 0.17, green: 0.52, blue: 0.44)],
                    glow: Color(red: 0.28, green: 0.74, blue: 0.54),
                    action: saveUpdateProgressMode
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

    private func intentionProgressSummaryText(for row: IntentionProgressRow) -> String {
        let currentValue = ManualProgressDisplayPolicy.displayedTotal(
            stored: row.total,
            draft: sliderValues[row.intention.id],
            isEditing: isUpdateProgressMode
        )
        let isWeekly = row.intention.timeframe.lowercased() == "weekly"
        let targetValue = isWeekly ? row.intention.targetValue / 7.0 : row.intention.targetValue
        let paceNote = isWeekly ? " today · weekly pace" : " today"
        return "\(formattedProgressValue(currentValue)) / \(formattedProgressValue(targetValue)) \(compactUnit(row.intention.unit))\(paceNote)"
    }

    private func manualProgressSlider(for row: IntentionProgressRow, tint: Color) -> some View {
        ZStack {
            HStack(spacing: 0) {
                ForEach(Array(ManualProgressSliderPolicy.tickPercents.enumerated()), id: \.offset) { index, _ in
                    Capsule()
                        .fill(
                            index == 0 || index == ManualProgressSliderPolicy.segmentCount
                                ? AttuneTheme.textTertiary.opacity(0.7)
                                : AttuneTheme.textTertiary.opacity(0.5)
                        )
                        .frame(width: 1.5, height: index.isMultiple(of: 2) ? 9 : 6)
                    if index < ManualProgressSliderPolicy.segmentCount {
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 15)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            Slider(
                value: Binding(
                    get: { percentForTotal(sliderValues[row.intention.id] ?? row.total, intention: row.intention) },
                    set: { newPercent in
                        let adjustedPercent = ManualProgressSliderPolicy.adjustedPercent(newPercent)
                        sliderValues[row.intention.id] = totalForPercent(adjustedPercent, intention: row.intention)
                        updateProgressSnapFeedback(rawPercent: newPercent, intentionID: row.intention.id)
                    }
                ),
                in: 0...1
            )
            .tint(tint)
            .accessibilityLabel("Progress for \(row.intention.title)")
            .accessibilityValue("\(Int((currentPercent(for: row) * 100).rounded())) percent")
        }
        .frame(minHeight: 30)
    }

    /// Adjacent intentions walk around the color wheel using a non-repeating
    /// interval. The title stays close to white while the progress line uses a
    /// more saturated version of the exact same hue.
    private func intentionNeonTextColor(at index: Int) -> Color {
        Color(
            hue: intentionNeonHue(at: index),
            saturation: 0.30,
            brightness: 1.0
        )
    }

    private func intentionNeonAccentColor(at index: Int) -> Color {
        Color(
            hue: intentionNeonHue(at: index),
            saturation: 0.78,
            brightness: 1.0
        )
    }

    private func intentionNeonHue(at index: Int) -> Double {
        (0.48 + Double(index) * 0.173).truncatingRemainder(dividingBy: 1)
    }

    private func updateProgressSnapFeedback(rawPercent: Double, intentionID: String) {
        guard let tickIndex = ManualProgressSliderPolicy.nearbyTickIndex(for: rawPercent) else {
            activeProgressSnapTicks[intentionID] = nil
            return
        }
        guard activeProgressSnapTicks[intentionID] != tickIndex else { return }
        activeProgressSnapTicks[intentionID] = tickIndex
        ManualProgressHaptics.crossedTick()
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
    
    @ViewBuilder
    private var weeklyMomentumCard: some View {
        switch HomeWeeklyMomentumDesign.active {
        case .dayTiles:
            weeklyMomentumDayTileCard
        case .depthDials:
            weeklyMomentumDepthDialCard
        case .classicBars:
            classicWeeklyMomentumCard
        }
    }

    /// A literal seven-day mosaic: every tile names the day and prints its
    /// percentage, while color and fill act only as supporting cues.
    private var weeklyMomentumDayTileCard: some View {
        Button(action: {
            appRouter.navigateToMomentum(date: Date())
        }) {
            VStack(alignment: .leading, spacing: 14) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        weeklyMomentumDayTileTitle
                        weeklyMomentumDayTileSummary
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        weeklyMomentumDayTileTitle
                        Spacer(minLength: 8)
                        weeklyMomentumDayTileSummary
                    }
                }

                WeeklyMomentumDayTileStrip(
                    days: weekMomentum.days,
                    colorForProgress: colorForProgressRatio
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 15)
            .padding(.bottom, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .attuneCard()
        .accessibilityHint("Opens detailed Momentum history")
    }

    private var weeklyMomentumDayTileTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("THIS WEEK")
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(AttuneTheme.accent)
            Text("Daily intention progress")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AttuneTheme.textPrimary)
            Text("Each tile shows that day's progress.")
                .font(.caption2)
                .foregroundStyle(AttuneTheme.textSecondary)
        }
    }

    private var weeklyMomentumDayTileSummary: some View {
        HStack(spacing: 7) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(weeklyMomentumAverageRatio.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(weeklyMomentumAverageColor)
                Text(weeklyMomentumAverageRatio == nil ? "no entries yet" : "week average")
                    .font(.caption2)
                    .foregroundStyle(AttuneTheme.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AttuneTheme.accent)
        }
    }

    /// A seven-point 3D path made from radial progress dials. The dial arc and
    /// its vertical position both express progress, while labels remain on one
    /// fixed baseline for calm, uniform scanning.
    private var weeklyMomentumDepthDialCard: some View {
        Button(action: {
            appRouter.navigateToMomentum(date: Date())
        }) {
            ZStack {
                WeeklyMomentumCardAtmosphere()

                VStack(alignment: .leading, spacing: 16) {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 7) {
                            weeklyMomentumDepthTitle
                            weeklyMomentumDepthSummary
                        }
                    } else {
                        HStack(alignment: .top, spacing: 12) {
                            weeklyMomentumDepthTitle
                            Spacer(minLength: 8)
                            weeklyMomentumDepthSummary
                        }
                    }

                    if weekMomentum.days.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "circle.dotted")
                                .foregroundStyle(AttuneTheme.accent)
                            Text("Your week will take shape after your first check-in.")
                                .font(.caption)
                                .foregroundStyle(AttuneTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)
                    } else {
                        WeeklyMomentumDepthChart(
                            days: weekMomentum.days,
                            colorForProgress: colorForProgressRatio
                        )
                        .frame(height: 112)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 14)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .attuneCard()
        .accessibilityHint("Opens detailed Momentum history")
    }

    private var weeklyMomentumDepthTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("THIS WEEK")
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(AttuneTheme.accent)
            Text("Momentum path")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AttuneTheme.textPrimary)
        }
    }

    private var weeklyMomentumDepthSummary: some View {
        HStack(spacing: 7) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(weeklyMomentumAverageText)
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(weeklyMomentumAverageColor)
                Text(weeklyMomentumAverageCaption)
                    .font(.caption2)
                    .foregroundStyle(AttuneTheme.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AttuneTheme.accent)
        }
    }

    private var weeklyMomentumMeasuredDays: [DayMomentum] {
        weekMomentum.days.filter { !$0.isFutureDay && $0.hasData && $0.completionRatio != nil }
    }

    private var weeklyMomentumAverageRatio: Double? {
        let ratios = weeklyMomentumMeasuredDays.compactMap(\.completionRatio)
        guard !ratios.isEmpty else { return nil }
        return ratios.reduce(0, +) / Double(ratios.count)
    }

    private var weeklyMomentumAverageText: String {
        guard let ratio = weeklyMomentumAverageRatio else { return "READY" }
        return "\(Int((ratio * 100).rounded()))%"
    }

    private var weeklyMomentumAverageCaption: String {
        weeklyMomentumAverageRatio == nil ? "start your path" : "average so far"
    }

    private var weeklyMomentumAverageColor: Color {
        guard let ratio = weeklyMomentumAverageRatio else { return AttuneTheme.accent }
        return colorForProgressRatio(ratio)
    }

    /// Original Home weekly card, intentionally retained byte-for-byte in
    /// behavior so the redesign can be reverted via HomeWeeklyMomentumDesign.
    private var classicWeeklyMomentumCard: some View {
        Button(action: {
            appRouter.navigateToMomentum(date: Date())  // Jump to Library → Momentum showing today
        }) {
            VStack(alignment: .leading, spacing: 5) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("This Week")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AttuneTheme.textPrimary)
                        Label("View Momentum", systemImage: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(AttuneTheme.accent)
                    }
                } else {
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
        activeProgressSnapTicks = [:]
        isUpdateProgressMode = true // toggle mode on
        ManualProgressHaptics.editorOpened()
    }
    
    /// Cancels update mode and restores original displayed totals without saving.
    private func cancelUpdateProgressMode() {
        isUpdateProgressMode = false // exit mode
        sliderValues = [:]
        originalTotals = [:]
        activeProgressSnapTicks = [:]
        loadTodaysProgress() // refresh to ensure UI reflects persisted state
        loadIntentionsBreakdown() // recompute counts from live data
    }
    
    /// Saves overrides only for intentions whose slider totals actually changed.
    private func saveUpdateProgressMode() {
        guard currentIntentionSet != nil else { // ensure we have a set
            isUpdateProgressMode = false // bail out to safe state
            return // nothing to save
        }
        let previousPercents = displayedProgressPercentages()
        let dateKey = ProgressCalculator.dateKey(for: Date()) // today’s date key
        let savedAt = Date() // one timestamp keeps multiple real changes in the same manual chart cluster
        var savedChangeCount = 0
        for row in todaysProgress { // iterate intentions shown
            let value = sliderValues[row.intention.id] ?? row.total // use slider or existing total
            let originalValue = originalTotals[row.intention.id] ?? row.total
            guard ManualProgressSavePolicy.hasChanged(current: value, original: originalValue) else { continue }
            let override = ManualProgressOverride( // build override payload
                dateKey: dateKey, // apply to today
                intentionId: row.intention.id, // target intention
                amount: value, // slider total
                unit: row.intention.unit, // preserve unit for display
                updatedAt: savedAt
            )
            do {
                try OverrideStore.shared.setOverride(override)
                savedChangeCount += 1
            } catch {
                AppLogger.log(AppLogger.ERR, "Manual progress metrics save skipped after override failure id=\(AppLogger.shortId(row.intention.id))")
            }
        }
        EngagementMetricsStore.shared.record(.manualProgressUpdated, quantity: savedChangeCount, at: savedAt)
        isUpdateProgressMode = false // exit mode
        sliderValues = [:]
        originalTotals = [:]
        activeProgressSnapTicks = [:]
        loadTodaysProgress() // refresh data to reflect overrides
        loadIntentionsBreakdown() // recompute counts
        let visiblyChangedIDs = changedProgressIntentionIDs(since: previousPercents)
        highlightProgressRows(visiblyChangedIDs)
        if !visiblyChangedIDs.isEmpty {
            ManualProgressHaptics.savedChanges()
        }
    }

    /// Returns the currently visible progress percentage for each intention row.
    private func displayedProgressPercentages() -> [String: Double] {
        Dictionary(uniqueKeysWithValues: todaysProgress.map { ($0.id, $0.percent) })
    }

    /// Limits feedback to rows whose displayed percentage changed after a save.
    private func changedProgressIntentionIDs(since previousPercents: [String: Double]) -> Set<String> {
        Set(todaysProgress.compactMap { row in
            guard let previous = previousPercents[row.id],
                  abs(previous - row.percent) > 0.000_001 else { return nil }
            return row.id
        })
    }

    /// Shows a short success highlight, then restores the ordinary row appearance.
    private func highlightProgressRows(_ intentionIDs: Set<String>) {
        guard !intentionIDs.isEmpty else { return }

        let token = UUID()
        progressHighlightToken = token
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            highlightedProgressIntentionIDs = intentionIDs
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard progressHighlightToken == token else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.55)) {
                highlightedProgressIntentionIDs = []
            }
        }
    }
    
    /// Computes current percent for a row using live or slider value.
    private func currentPercent(for row: IntentionProgressRow) -> Double {
        let value = ManualProgressDisplayPolicy.displayedTotal(
            stored: row.total,
            draft: sliderValues[row.intention.id],
            isEditing: isUpdateProgressMode
        )
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
                .frame(height: 44) // meet the minimum touch target while keeping a compact pill
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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    moodControl
                    Divider().overlay(AttuneTheme.border)
                    streakSummary
                }
            } else {
                HStack(spacing: 0) {
                    moodControl
                    Rectangle()
                        .fill(AttuneTheme.border)
                        .frame(width: 1, height: 40)
                    streakSummary
                }
            }
        }
        .attuneCard()
    }

    private var moodControl: some View {
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
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasMoodSet ? "Mood \(moodScoreToday) out of 10, \(moodSummaryText)" : "Set today's mood")
    }

    private var streakSummary: some View {
        HStack(spacing: 9) {
            Image(systemName: "flame.fill")
                .font(.title3)
                .foregroundStyle(AttuneTheme.accent)
                .frame(width: 34, height: 34)
                .background(AttuneTheme.accent.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
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
        .accessibilityLabel("Streak")
        .accessibilityValue("\(streak) \(streak == 1 ? "day" : "days")")
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
                    .accessibilityHidden(true)
                Text("Listening")
                    .font(.headline)
                Spacer()
                Text(elapsedFormatted)
                    .font(.headline.monospacedDigit())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recording check-in")
            .accessibilityValue(elapsedFormatted)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(detail)
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
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                state = .idle
            }
            if case .saved = newState {
                scheduleReviewRequestAfterSavedReceipt()
            }
        }
    }

    private func completeCheckIn(_ checkInId: String) {
        EngagementMetricsStore.shared.record(
            .checkInCompleted,
            eventID: "check-in-completed:\(checkInId)",
            at: Date()
        )
        state = .saved(checkInId: checkInId)
    }

    private func scheduleReviewRequestAfterSavedReceipt() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard scenePhase == .active,
                  appRouter.selectedRootTab == .home,
                  state == .idle,
                  !showEditIntentions,
                  !showMoodEditor,
                  !showSuggestionEditor,
                  !showSuggestionEvidence,
                  !showAllCheckInsSheet,
                  !showPaywall,
                  ambiguitySheetData == nil,
                  suggestionToastCenter.homeSuggestion == nil,
                  !isGeneratingSuggestion else {
                return
            }

            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            guard EngagementMetricsStore.shared.claimReviewRequestIfEligible(currentVersion: version) else {
                return
            }
            requestReview()
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
        evaluateOneThingMode()
        updateSuggestedReplacement()
    }

    private func evaluateIntentionSuggestion(shouldPresentToast: Bool = false) async {
        guard IntentionSuggestionFeature.isEnabled else { return }
        do {
            try IntentionSuggestionStore.shared.bootstrapExistingInstallIfNeeded()
            let snapshot = IntentionSuggestionStore.shared.load()
            let sessions = SessionStore.shared.loadAllSessions()
            let topics = IntentionSuggestionEngine.makeTopics(
                topics: SessionRecapTopicSnapshotReader.load(),
                sessions: sessions,
                items: ExtractionStore.shared.loadAllExtractions(),
                corrections: CorrectionsStore.shared.loadCorrections(),
                rapidTestingEnabled: RapidIntentionSuggestionTestingFeature.isEnabled
            )
            let activeSet = IntentionSetStore.shared.loadCurrentIntentionSet()
            let activeIntentions = IntentionStore.shared.loadIntentions(ids: activeSet?.intentionIds ?? [])
            suggestedReplacement = replacementCandidateIfNeeded(
                activeIntentions: activeIntentions,
                intentionSet: activeSet
            )
            let decision = IntentionSuggestionEngine.decide(
                snapshot: snapshot,
                topics: topics,
                completedSessionCount: sessions.filter { $0.status == "complete" }.count,
                isAtIntentionLimit: !subscriptionManager.canAddIntention(currentCount: activeIntentions.count),
                rapidTestingEnabled: RapidIntentionSuggestionTestingFeature.isEnabled
            )
            switch decision {
            case .show(let suggestion):
                guard !IntentionSuggestionEngine.isCoveredByActiveIntention(
                    suggestionTitle: suggestion.title,
                    activeIntentions: activeIntentions
                ) else {
                    // Covers outstanding suggestions created before the active
                    // intention existed, including older app versions.
                    try IntentionSuggestionStore.shared.decide(.accepted, suggestion: suggestion)
                    intentionSuggestion = nil
                    suggestionToastCenter.resolveSuggestion(id: suggestion.id)
                    return
                }
                intentionSuggestion = suggestion
                suggestionNudge = nil
                if shouldPresentToast {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.84)) {
                        suggestionToastCenter.presentAfterProcessing(suggestion)
                    }
                }
            case .nudgeToRecord(let key):
                suggestionNudge = "Talk it out a few times so Attune can notice a recurring theme before suggesting anything."
                try IntentionSuggestionStore.shared.recordNudge(opportunityKey: key)
            case .consume(let key):
                try IntentionSuggestionStore.shared.consume(opportunityKey: key)
            case .none:
                break
            case .request(let topic, let opportunityKey):
                isGeneratingSuggestion = true
                defer { isGeneratingSuggestion = false }
                try IntentionSuggestionStore.shared.recordAttempt(opportunityKey: opportunityKey)
                let generatedSuggestion = try await IntentionSuggestionService.generate(
                    topic: topic,
                    activeIntentions: activeIntentions,
                    history: snapshot.history,
                    recentProgressDaysByIntentionId: recentProgressDaysByIntentionId(
                        intentions: activeIntentions,
                        intentionSet: activeSet
                    ),
                    rapidTestMode: RapidIntentionSuggestionTestingFeature.isEnabled
                )
                guard let suggestion = generatedSuggestion else {
                    if RapidIntentionSuggestionTestingFeature.isEnabled {
                        suggestionNudge = "Rapid test qualified three mentions, but no safe new suggestion was returned."
                    }
                    return
                }
                guard !IntentionSuggestionEngine.isCoveredByActiveIntention(
                          suggestionTitle: suggestion.title,
                          activeIntentions: activeIntentions
                      ),
                      !IntentionSuggestionEngine.isSuppressed(
                          actionId: suggestion.actionId,
                          actionFingerprint: suggestion.actionFingerprint,
                          title: suggestion.title,
                          history: snapshot.history
                      ) else {
                    return
                }
                try IntentionSuggestionStore.shared.setOutstanding(suggestion)
                intentionSuggestion = suggestion
                suggestionNudge = nil
                if shouldPresentToast {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.84)) {
                        suggestionToastCenter.presentAfterProcessing(suggestion)
                    }
                }
            }
        } catch {
            AppLogger.log(AppLogger.ERR, "Intention suggestion unavailable error=\"\(error.localizedDescription)\"")
            if RapidIntentionSuggestionTestingFeature.isEnabled {
                suggestionNudge = "Rapid suggestion test failed. Check the app log and Worker deployment."
            }
        }
    }

    private func declineSuggestion(_ suggestion: SuggestedIntentionAction) {
        do {
            try IntentionSuggestionStore.shared.decide(.declined, suggestion: suggestion)
            intentionSuggestion = nil
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.34)) {
                suggestionToastCenter.resolveSuggestion(id: suggestion.id)
            }
        } catch {
            AppLogger.log(AppLogger.ERR, "Suggestion decline failed error=\"\(error.localizedDescription)\"")
        }
    }

    private func acceptSuggestion(_ suggestion: SuggestedIntentionAction) {
        do {
            try IntentionSuggestionStore.shared.decide(.accepted, suggestion: suggestion)
            intentionSuggestion = nil
            suggestionToastCenter.resolveSuggestion(id: suggestion.id)
            refreshAll()
        } catch {
            AppLogger.log(AppLogger.ERR, "Suggestion acceptance state failed error=\"\(error.localizedDescription)\"")
        }
    }

    private func autoDismissHomeSuggestion(_ suggestion: SuggestedIntentionAction) async {
        guard !UIAccessibility.isVoiceOverRunning else { return }
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.78)) {
            suggestionToastCenter.dismissHomeSuggestion(id: suggestion.id)
        }
    }

    private func suggestionToastTransition(edge: Edge) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: edge).combined(with: .opacity),
                removal: .move(edge: edge).combined(with: .opacity)
            )
    }

    private func evaluateOneThingMode(now: Date = Date()) {
        guard OneThingModeFeature.isEnabled else {
            oneThingMode = .empty
            return
        }
        guard let intentionSet = IntentionSetStore.shared.loadCurrentIntentionSet() else {
            oneThingMode = .empty
            return
        }
        let intentions = IntentionStore.shared.loadIntentions(ids: intentionSet.intentionIds).filter(\.isActive)
        var state = OneThingModeStore.shared.load()
        if state.isActive, !intentions.contains(where: { $0.id == state.focusedIntentionId }) {
            if let first = intentions.first {
                try? OneThingModeStore.shared.select(first.id)
                state = OneThingModeStore.shared.load()
            } else {
                try? OneThingModeStore.shared.exit(now: now)
                state = .empty
            }
        }

        let activityKeys = recentActivityDateKeys(days: 2, intentionSet: intentionSet, now: now)
        if OneThingModePolicy.shouldActivate(
            state: state,
            intentionSetStartedAt: intentionSet.startedAt,
            activeIntentionCount: intentions.count,
            activityDateKeys: activityKeys,
            now: now
        ), let first = intentions.first {
            do {
                try OneThingModeStore.shared.activate(focusedIntentionId: first.id, now: now)
                state = OneThingModeStore.shared.load()
            } catch {
                AppLogger.log(AppLogger.ERR, "One Thing Mode activation failed error=\"\(error.localizedDescription)\"")
            }
        }
        oneThingMode = state
    }

    private func selectOneThing(_ intentionId: String) {
        do {
            try OneThingModeStore.shared.select(intentionId)
            oneThingMode = OneThingModeStore.shared.load()
        } catch {
            AppLogger.log(AppLogger.ERR, "One Thing Mode selection failed error=\"\(error.localizedDescription)\"")
        }
    }

    private func exitOneThingMode() {
        do {
            try OneThingModeStore.shared.exit()
            oneThingMode = OneThingModeStore.shared.load()
        } catch {
            AppLogger.log(AppLogger.ERR, "One Thing Mode exit failed error=\"\(error.localizedDescription)\"")
        }
    }

    private func updateSuggestedReplacement() {
        guard let set = IntentionSetStore.shared.loadCurrentIntentionSet() else {
            suggestedReplacement = nil
            return
        }
        let active = IntentionStore.shared.loadIntentions(ids: set.intentionIds).filter(\.isActive)
        suggestedReplacement = replacementCandidateIfNeeded(activeIntentions: active, intentionSet: set)
    }

    private func replacementCandidateIfNeeded(
        activeIntentions: [Intention],
        intentionSet: IntentionSet?
    ) -> Intention? {
        guard !subscriptionManager.canAddIntention(currentCount: activeIntentions.count),
              let intentionSet else { return nil }
        let keys = previousDateKeys(days: 3)
        var totals: [String: [Double]] = [:]
        for key in keys {
            let entries = ProgressStore.shared.loadEntries(dateKey: key, intentionSetId: intentionSet.id)
            let overrides = OverrideStore.shared.loadOverridesForDate(dateKey: key)
            for intention in activeIntentions {
                totals[intention.id, default: []].append(
                    ProgressCalculator.totalForIntention(
                        entries: entries,
                        dateKey: key,
                        intentionId: intention.id,
                        intentionSetId: intentionSet.id,
                        overrideAmount: overrides[intention.id]
                    )
                )
            }
        }
        return OneThingModePolicy.replacementCandidate(intentions: activeIntentions, dailyTotals: totals)
    }

    private func recentActivityDateKeys(days: Int, intentionSet: IntentionSet, now: Date) -> Set<String> {
        let keys = Set(previousDateKeys(days: days, now: now))
        var active = Set(ProgressStore.shared.loadAllProgressEntries().filter {
            $0.intentionSetId == intentionSet.id && keys.contains($0.dateKey)
        }.map(\.dateKey))
        for key in keys where !OverrideStore.shared.loadOverrideRecordsForDate(dateKey: key).isEmpty {
            active.insert(key)
        }
        return active
    }

    private func previousDateKeys(days: Int, now: Date = Date()) -> [String] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (1...days).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { ProgressCalculator.dateKey(for: $0) }
        }
    }

    private func recentProgressDaysByIntentionId(
        intentions: [Intention],
        intentionSet: IntentionSet?,
        now: Date = Date()
    ) -> [String: Int] {
        guard let intentionSet else { return [:] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let keys = Set((0..<14).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { ProgressCalculator.dateKey(for: $0) }
        })
        let activeIDs = Set(intentions.map(\.id))
        let grouped = Dictionary(grouping: ProgressStore.shared.loadAllProgressEntries().filter {
            $0.intentionSetId == intentionSet.id && activeIDs.contains($0.intentionId) && keys.contains($0.dateKey)
        }, by: \.intentionId)
        return grouped.mapValues { Set($0.map(\.dateKey)).count }
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
                try advanceManualOverrideIfNeeded(
                    dateKey: context.dateKey,
                    intentionId: r.update.intentionId,
                    updateType: updateType,
                    amount: r.update.amount,
                    unit: r.update.unit
                )
            } catch {
                AppLogger.log(AppLogger.ERR, "Ambiguity resolve save failed id=\(AppLogger.shortId(r.update.intentionId)) error=\"\(error.localizedDescription)\"")
            }
        }
    }

    /// Keeps a prior manual total moving when a later voice update arrives.
    /// Without this, the saved override masks new entries on the Today screen.
    private func advanceManualOverrideIfNeeded(
        dateKey: String,
        intentionId: String,
        updateType: String,
        amount: Double,
        unit: String
    ) throws {
        guard let existing = OverrideStore.shared.loadOverride(
            dateKey: dateKey,
            intentionId: intentionId
        ) else { return }

        let updatedAmount: Double
        switch updateType {
        case "TOTAL":
            updatedAmount = amount
        case "INCREMENT":
            updatedAmount = existing.amount + amount
        default:
            return
        }

        try OverrideStore.shared.setOverride(
            ManualProgressOverride(
                dateKey: dateKey,
                intentionId: intentionId,
                amount: max(0, updatedAmount),
                unit: unit.isEmpty ? existing.unit : unit
            )
        )
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
            let checkInId = try checkInRecorder.startRecording()
            EngagementMetricsStore.shared.record(
                .checkInStarted,
                eventID: "check-in-started:\(checkInId)"
            )
            
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
            let previousPercents = displayedProgressPercentages()
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
                    try advanceManualOverrideIfNeeded(
                        dateKey: dateKey,
                        intentionId: update.intentionId,
                        updateType: update.updateType,
                        amount: update.amount,
                        unit: update.unit
                    )
                    // Log applied update with new total for debugging
                    let entries = ProgressStore.shared.loadEntries(dateKey: dateKey, intentionSetId: intentionSet.id)
                    let currentOverride = OverrideStore.shared.loadOverride(
                        dateKey: dateKey,
                        intentionId: update.intentionId
                    )?.amount
                    let newTotal = ProgressCalculator.totalForIntention(
                        entries: entries,
                        dateKey: dateKey,
                        intentionId: update.intentionId,
                        intentionSetId: intentionSet.id,
                        overrideAmount: currentOverride
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

            refreshAll()
            highlightProgressRows(changedProgressIntentionIDs(since: previousPercents))

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
                completeCheckIn(checkInId)
            }
            
        } catch {
            AppLogger.log(AppLogger.ERR, "Check-in transcription failed id=\(AppLogger.shortId(checkInId)) error=\"\(error.localizedDescription)\"")
            EngagementMetricsStore.shared.record(
                .checkInFailed,
                eventID: "check-in-failed:\(checkInId)"
            )
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

/// Seven literal day tiles make the compact Home summary self-explanatory:
/// the printed percentage is primary and the rising color is redundant.
private struct WeeklyMomentumDayTileStrip: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let days: [DayMomentum]
    let colorForProgress: (Double) -> Color

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                    spacing: 8
                ) {
                    tiles
                }
            } else {
                HStack(spacing: 6) {
                    tiles
                }
            }
        }
    }

    @ViewBuilder
    private var tiles: some View {
        ForEach(days) { day in
            WeeklyMomentumDayTile(
                day: day,
                color: day.completionRatio.map(colorForProgress) ?? AttuneTheme.textTertiary
            )
            .frame(maxWidth: .infinity)
            .frame(height: 92)
        }
    }
}

private struct WeeklyMomentumDayTile: View {
    let day: DayMomentum
    let color: Color

    private var isToday: Bool {
        Calendar.current.isDateInToday(day.date)
    }

    private var visibleRatio: Double? {
        guard !day.isFutureDay, day.hasData, let ratio = day.completionRatio else { return nil }
        return min(1, max(0, ratio))
    }

    private var percentageText: String {
        guard let ratio = visibleRatio else { return "—" }
        return "\(Int((ratio * 100).rounded()))%"
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white.opacity(0.055))

                if let ratio = visibleRatio {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.48), color.opacity(0.15)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: max(7, geometry.size.height * CGFloat(ratio)))
                        .padding(2)
                        .shadow(color: color.opacity(0.34), radius: 6, y: 2)
                }

                VStack(spacing: 0) {
                    Text(day.weekdayLetter)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isToday ? AttuneTheme.accent : AttuneTheme.textSecondary)

                    Spacer(minLength: 4)

                    Text(percentageText)
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(visibleRatio == nil ? AttuneTheme.textTertiary : Color.white)
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)

                    Circle()
                        .fill(isToday ? AttuneTheme.accent : Color.clear)
                        .frame(width: 5, height: 5)
                        .padding(.top, 7)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 9)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(
                        isToday ? AttuneTheme.accent.opacity(0.88) : Color.white.opacity(0.09),
                        lineWidth: isToday ? 1.4 : 0.7
                    )
            }
            .opacity(day.isFutureDay ? 0.42 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let prefix = isToday ? "Today, " : ""
        if day.isFutureDay { return "\(prefix)\(day.weekdayLetter), future day" }
        guard visibleRatio != nil else { return "\(prefix)\(day.weekdayLetter), no progress entry" }
        return "\(prefix)\(day.weekdayLetter), \(percentageText) intention progress"
    }
}

/// Low-contrast depth and light inside the new card. It stays deliberately
/// quieter than the Today's Intentions treatment so the progress colors lead.
private struct WeeklyMomentumCardAtmosphere: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [
                        AttuneTheme.accent.opacity(0.08),
                        Color.clear,
                        AttuneTheme.accentSecondary.opacity(0.07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(AttuneTheme.accent.opacity(0.10))
                    .frame(width: geometry.size.width * 0.7)
                    .blur(radius: 32)
                    .offset(x: geometry.size.width * 0.34, y: -geometry.size.height * 0.46)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A weekly radial plot: each progress dial sits higher as its completion
/// increases, and a shallow extruded connector turns the seven readings into
/// one continuous path rather than seven independent bars.
private struct WeeklyMomentumDepthChart: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let days: [DayMomentum]
    let colorForProgress: (Double) -> Color

    @State private var hasAppeared = false

    private let plotTop: CGFloat = 4
    private let plotTravel: CGFloat = 42
    private let labelY: CGFloat = 101

    var body: some View {
        GeometryReader { geometry in
            let slotWidth = geometry.size.width / CGFloat(max(days.count, 1))

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let visibleIndices = days.indices.filter { !days[$0].isFutureDay }
                    guard let firstIndex = visibleIndices.first else { return }

                    var path = Path()
                    path.move(to: point(for: firstIndex, slotWidth: slotWidth))
                    for index in visibleIndices.dropFirst() {
                        path.addLine(to: point(for: index, slotWidth: slotWidth))
                    }

                    var depthPath = path
                    depthPath = depthPath.applying(CGAffineTransform(translationX: 0, y: 5))
                    context.stroke(
                        depthPath,
                        with: .color(Color.black.opacity(0.32)),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                    )
                    context.stroke(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [
                                AttuneTheme.accent.opacity(0.34),
                                Color.white.opacity(0.25),
                                AttuneTheme.accentSecondary.opacity(0.34)
                            ]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: size.width, y: 0)
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                }
                .opacity(hasAppeared || reduceMotion ? 1 : 0)
                .animation(.easeOut(duration: 0.45), value: hasAppeared)

                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    let ratio = min(1, max(0, day.completionRatio ?? 0))
                    let isToday = Calendar.current.isDateInToday(day.date)

                    MomentumDepthDial(
                        progress: ratio,
                        color: colorForProgress(ratio),
                        isFuture: day.isFutureDay,
                        hasData: day.hasData,
                        isToday: isToday,
                        isVisible: hasAppeared || reduceMotion
                    )
                    .frame(width: min(38, slotWidth - 4), height: 38)
                    .position(point(for: index, slotWidth: slotWidth))
                    .animation(
                        reduceMotion
                            ? nil
                            : .spring(response: 0.62, dampingFraction: 0.72)
                                .delay(Double(index) * 0.055),
                        value: hasAppeared
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(for: day, isToday: isToday))

                    VStack(spacing: 3) {
                        Text(day.weekdayLetter)
                            .font(.caption.weight(isToday ? .bold : .semibold))
                            .foregroundStyle(isToday ? AttuneTheme.textPrimary : AttuneTheme.textSecondary)
                        Capsule()
                            .fill(isToday ? AttuneTheme.accent : Color.clear)
                            .frame(width: 12, height: 2)
                    }
                    .frame(width: slotWidth)
                    .position(x: (CGFloat(index) + 0.5) * slotWidth, y: labelY)
                    .accessibilityHidden(true)
                }
            }
        }
        .task(id: days.map(\.id)) {
            hasAppeared = reduceMotion
            if !reduceMotion {
                await Task.yield()
                hasAppeared = true
            }
        }
    }

    private func point(for index: Int, slotWidth: CGFloat) -> CGPoint {
        let day = days[index]
        let ratio = min(1, max(0, day.completionRatio ?? 0))
        let y = day.isFutureDay ? plotTop + plotTravel : plotTop + (1 - ratio) * plotTravel
        return CGPoint(x: (CGFloat(index) + 0.5) * slotWidth, y: y + 19)
    }

    private func accessibilityLabel(for day: DayMomentum, isToday: Bool) -> String {
        let prefix = isToday ? "Today, " : ""
        if day.isFutureDay { return "\(prefix)\(day.weekdayLetter), future day" }
        guard day.hasData, let ratio = day.completionRatio else {
            return "\(prefix)\(day.weekdayLetter), no momentum data"
        }
        return "\(prefix)\(day.weekdayLetter), \(Int((ratio * 100).rounded())) percent momentum"
    }
}

/// A compact progress ring with a darker lower rim and offset highlight. The
/// layered rim reads as a small physical dial without adding visual noise.
private struct MomentumDepthDial: View {
    let progress: Double
    let color: Color
    let isFuture: Bool
    let hasData: Bool
    let isToday: Bool
    let isVisible: Bool

    var body: some View {
        ZStack {
            if isToday {
                Circle()
                    .stroke(color.opacity(0.22), lineWidth: 7)
                    .blur(radius: 5)
                    .scaleEffect(1.13)
            }

            Circle()
                .fill(Color.black.opacity(0.36))
                .offset(y: 4)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.10), AttuneTheme.surfaceStrong.opacity(0.96)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .stroke(AttuneTheme.border.opacity(isFuture ? 0.48 : 0.8), lineWidth: 4.5)

            if !isFuture && hasData {
                Circle()
                    .trim(from: 0, to: isVisible ? progress : 0)
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.52), color, Color.white.opacity(0.84), color],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.72), radius: 4, x: 0, y: 2)

                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .shadow(color: color.opacity(0.7), radius: 3)
            } else if !isFuture {
                Circle()
                    .fill(AttuneTheme.textSecondary.opacity(0.52))
                    .frame(width: 4, height: 4)
            }
        }
        .scaleEffect(isVisible ? 1 : 0.72)
        .opacity(isVisible ? (isFuture ? 0.42 : 1) : 0)
    }
}

#Preview {
    HomeView()
        .environmentObject(AppRouter())
}
