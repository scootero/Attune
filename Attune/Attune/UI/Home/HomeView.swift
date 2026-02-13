//
//  HomeView.swift
//  Attune
//
//  Home tab: intentions, progress, mood, streak, check-in recording.
//  SLICE 1–4: Recording + GPT extraction. SLICE 5: Full UX.
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
    
    var body: some View {
        NavigationView {
        VStack(spacing: 0) {
            // Scrollable content: progress, sessions, mood (CTA stays fixed below)
            ScrollView {
                VStack(spacing: 24) {
                    Text("Home")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.top, 40)
                    
                    currentIntentionsSection
                    if !todaysProgress.isEmpty { intentionsListSection }
                    todayCheckInsSection
                    moodSection
                    
                    Spacer(minLength: 40)
                }
            }
            
            // Fixed CTA area: stable placement at bottom, doesn't scroll; saved/error as compact banners
            VStack(spacing: 12) {
                recordCheckInCTAArea
                streakSection
            }
            .padding()
            .background(Color(.systemBackground))
            .overlay(alignment: .top) {
                Divider()
            }
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
    
    // MARK: - A) Current Intentions Header
    
    private var currentIntentionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Current Intentions")
                    .font(.headline)
                Spacer()
                Button(action: { showEditIntentions = true }) {
                    Text("Edit")
                }
            }
            
            if let set = currentIntentionSet {
                Text("Started \(set.startedAt, format: .dateTime.month().day().year())")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if todaysProgress.isEmpty {
                Text("No intentions yet. Add one to start tracking.")
                    .font(.body)
                    .foregroundColor(.secondary)
                Button(action: { showEditIntentions = true }) {
                    Label("Add Intention", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // MARK: - B) Intentions List
    
    private var intentionsListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's progress")
                .font(.headline)
            
            // Use enumerated() so ForEach iterates over (Int, IntentionProgressRow) — no Binding overload applies.
            ForEach(Array(todaysProgress.enumerated()), id: \.element.id) { _, row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.intention.title)
                            .font(.body)
                        Spacer()
                        Text(formatProgress(row.intention, total: row.total))
                            .font(.body)
                            .foregroundColor(.secondary)
                        Text("\(Int(row.percent * 100))%")
                            .font(.body.monospacedDigit())
                    }
                    SwiftUI.ProgressView(value: row.percent)
                        .tint(.accentColor)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private func formatProgress(_ intention: Intention, total: Double) -> String {
        String(format: "%.1f / %.1f \(intention.unit)", total, intention.targetValue)
    }
    
    // MARK: - B2) Today Check-ins Card
    
    /// Card showing today's check-ins with transcript snippets. Max 3 rows + "View all".
    /// Processing placeholder appears at top when recording completes; green/red flash on done.
    private var todayCheckInsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today Check-ins")
                    .font(.headline)
                Spacer()
                Button("View all") {
                    showAllCheckInsSheet = true
                }
                .font(.subheadline)
            }
            
            if todayCheckIns.isEmpty && processingCheckInId == nil && failedCheckInId == nil {
                Text("No check-ins today.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    // Processing placeholder at top (yellow, spinner)
                    if let id = processingCheckInId {
                        processingPlaceholderRow(id: id)
                    }
                    // Failed row (red) when transcription failed
                    if let id = failedCheckInId, let createdAt = failedCheckInCreatedAt {
                        failedCheckInRow(id: id, createdAt: createdAt)
                    }
                    // Up to 3 check-in rows (newest-first)
                    ForEach(todayCheckIns.prefix(3)) { checkIn in
                        NavigationLink(destination: CheckInDetailView(checkInId: checkIn.id)) {
                            todayCheckInRow(checkIn)
                        }
                        .buttonStyle(.plain)
                    }
                    // "View all" row when more than 3
                    if todayCheckIns.count > 3 {
                        Button(action: { showAllCheckInsSheet = true }) {
                            HStack {
                                Text("View all \(todayCheckIns.count) check-ins")
                                    .font(.subheadline)
                                    .foregroundColor(.accentColor)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(10)
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    /// Placeholder row while check-in is processing (yellow background, spinner)
    private func processingPlaceholderRow(id: String) -> some View {
        HStack(spacing: 12) {
            SwiftUI.ProgressView()
                .scaleEffect(0.9)
            Text("Processing…")
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(10)
        .background(Color.yellow.opacity(0.25))
        .cornerRadius(8)
    }
    
    /// Failed row when transcription failed (red background)
    private func failedCheckInRow(id: String, createdAt: Date) -> some View {
        let isHighlighted = highlightedCheckInId == id
        let bgColor = isHighlighted ? Color.red.opacity(0.2) : Color.red.opacity(0.12)
        
        return HStack(spacing: 8) {
            Text(createdAt.formatted(date: .omitted, time: .shortened))
                .font(.subheadline)
                .fontWeight(.medium)
            Text("Failed")
                .font(.caption)
                .foregroundColor(.red)
            Spacer()
        }
        .padding(10)
        .background(bgColor)
        .cornerRadius(8)
    }
    
    /// Single row for a check-in: time, 2-line transcript snippet. Green/red background when highlighted.
    private func todayCheckInRow(_ checkIn: CheckIn) -> some View {
        let isHighlighted = highlightedCheckInId == checkIn.id
        let bgColor: Color = {
            guard isHighlighted, let kind = highlightKind else { return Color(.systemBackground) }
            switch kind {
            case .success: return Color.green.opacity(0.2)
            case .failure: return Color.red.opacity(0.2)
            }
        }()
        
        return VStack(alignment: .leading, spacing: 4) {
            Text(checkIn.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.subheadline)
                .fontWeight(.medium)
            Text(checkInTranscriptSnippet(for: checkIn))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            if isHighlighted, highlightKind == .failure {
                Text("Failed")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(10)
        .background(bgColor)
        .cornerRadius(8)
    }
    
    /// Transcript snippet for check-in (first ~120 chars + ellipsis)
    private func checkInTranscriptSnippet(for checkIn: CheckIn) -> String {
        let text = checkIn.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "No transcript" }
        let prefix = String(text.prefix(120)).trimmingCharacters(in: .whitespaces)
        return prefix + (text.count > 120 ? "…" : "")
    }
    
    // MARK: - C) Mood Row
    
    private var moodSection: some View {
        Button(action: { showMoodEditor = true }) {
            HStack {
                Image(systemName: "face.smiling")
                    .foregroundColor(.secondary)
                Text(moodDisplayText)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
    
    private var moodDisplayText: String {
        if let mood = todayMood {
            var text = mood.moodLabel ?? "Set mood"
            if let score = mood.moodScore, score != 0 {
                text += " (\(score > 0 ? "+" : "")\(score))"
            }
            return text
        }
        return "Set mood"
    }
    
    // MARK: - D) Record Check-In CTA (stable placement; saved/error as compact banners)
    
    /// Single CTA area that stays fixed; all states rendered compactly (no layout shift)
    private var recordCheckInCTAArea: some View {
        VStack(spacing: 12) {
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
                    Label("Record Check-In", systemImage: "record.circle")
                        .font(.title2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
            case .error:
                Button(action: { state = .idle }) {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .font(.title2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private var recordCheckInSection: some View {
        Button(action: startCheckIn) {
            Label("Record Check-In", systemImage: "record.circle")
                .font(.title2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
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
            .tint(.red)
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
    
    // MARK: - E) Streak
    
    private var streakSection: some View {
        HStack {
            Image(systemName: "flame.fill")
                .foregroundColor(.orange)
            Text("Streak: \(streak) days")
                .font(.body)
        }
        .padding()
    }
    
    // MARK: - Data Loading
    
    private func refreshAll() {
        loadTodaysProgress()
        loadCurrentIntentionSet()
        loadTodayCheckIns()
        refreshMoodAndStreak()
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
}
