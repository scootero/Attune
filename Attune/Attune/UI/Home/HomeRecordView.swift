//
//  HomeRecordView.swift
//  Attune
//
//  Consumer-facing, user-started Listening Session screen. RecorderService remains
//  the source of truth for session creation, background capability, and processing.
//

import SwiftUI

extension Notification.Name {
    static let attuneListeningSessionDidFinishProcessing = Notification.Name("attune.listening.session.didFinishProcessing")
}
import UIKit

struct HomeRecordView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @ObservedObject private var suggestionToastCenter = IntentionSuggestionToastCenter.shared
    @StateObject private var recorder = RecorderService.shared
    @StateObject private var transcriptionQueue = TranscriptionQueue.shared
    @StateObject private var extractionQueue = ExtractionQueue.shared

    @State private var isRequestingPermission = false
    @State private var isCheckingAIUsage = false
    @State private var isProcessing = false
    @State private var processingSessionId: String?
    @State private var activeSessionId: String?
    @State private var startErrorMessage: String?
    @State private var processingCheckTimer: Timer?

    @State private var todaySessionsCount = 0
    @State private var todayInsightsCount = 0
    /// Briefly marks Today as refreshed after a Listening Session is fully saved.
    @State private var showsRecentSessionCompletion = false
    /// Number of saved captures produced by the just-finished session.
    @State private var recentInsightsAddedCount = 0
    /// Ensures an older delayed fade cannot clear newer completion feedback.
    @State private var completionFeedbackToken = UUID()
    @State private var showSessionsSheet = false
    @State private var showInsightsSheet = false
    @State private var showPaywall = false
    @State private var recapPreview: (sessionId: String, recap: SessionRecap)?
    @State private var recapDetailSessionId: String?
    @State private var recapPreviewToken = UUID()

    var body: some View {
        ZStack {
            AttuneScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    sessionHero
                    historyCard
                }
                .padding(.horizontal, AttuneTheme.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 104)
            }
            .scrollIndicators(.hidden)

            if let recapPreview {
                Button {
                    openRecapDetails(sessionId: recapPreview.sessionId)
                } label: {
                    SessionRecapPreviewCard(recap: recapPreview.recap)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AttuneTheme.horizontalPadding)
                .padding(.bottom, 88)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .bottom)),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        )
                )
                .zIndex(2)
                .accessibilityLabel("Session highlight. \(recapPreview.recap.headline)")
                .accessibilityHint("Opens the full session details")
            }

            if let suggestion = suggestionToastCenter.talkSuggestion {
                IntentionSuggestionToast(
                    suggestion: suggestion,
                    onReview: { reviewSuggestionFromTalk(suggestion) },
                    onDismiss: { declineSuggestionFromTalk(suggestion) }
                )
                .padding(.horizontal, AttuneTheme.horizontalPadding)
                .padding(.top, 8)
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(suggestionToastTransition(edge: .top))
                .zIndex(3)
                .task(id: suggestion.id) {
                    await autoDismissTalkSuggestion(suggestion)
                }
            }
        }
        .onAppear {
            loadTodayCounts()
            restoreProcessingStateIfNeeded()
            startProcessingCheck()
        }
        .onDisappear {
            processingCheckTimer?.invalidate()
            processingCheckTimer = nil
        }
        .onChange(of: recorder.isRecording) { wasRecording, isRecording in
            recorderStateChanged(wasRecording: wasRecording, isRecording: isRecording)
        }
        .sheet(isPresented: $showSessionsSheet, onDismiss: { loadTodayCounts() }) {
            NavigationView {
                SessionListView(sessions: SessionStore.shared.loadAllSessions())
                    .navigationTitle("Past sessions")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showSessionsSheet = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showInsightsSheet, onDismiss: { loadTodayCounts() }) {
            NavigationView {
                InsightsListView()
                    .navigationTitle("Captured")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showInsightsSheet = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(reason: "Talk it out and the Insights it creates are included with Attune Pro.")
                .environmentObject(subscriptionManager)
        }
        .sheet(
            isPresented: Binding(
                get: { recapDetailSessionId != nil },
                set: { if !$0 { recapDetailSessionId = nil } }
            )
        ) {
            if let sessionId = recapDetailSessionId {
                SessionRecapSheet(sessionId: sessionId)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Talk it out")
                .font(.title.bold())
                .foregroundStyle(AttuneTheme.textPrimary)
            Text("Think out loud, clear your head, and notice what keeps coming up.")
                .font(.subheadline)
                .foregroundStyle(AttuneTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sessionHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("TALK IT OUT", systemImage: "waveform.badge.mic")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(AttuneTheme.accent)

            if recorder.isRecording {
                recordingContent
            } else if isProcessing {
                processingContent
            } else if isRequestingPermission {
                permissionRequestContent
            } else if PermissionsHelper.recordingPermissionState == .denied {
                permissionDeniedContent
            } else {
                idleContent
            }
        }
        .padding(18)
        .attuneCard()
    }

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Say what’s on your mind")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AttuneTheme.textPrimary)
                Text("Attune records only after you start. It organizes clear intentions, commitments, events, and states, then groups repeated ideas into themes in Insights. You can leave the app or lock your phone while you’re talking.")
                    .font(.subheadline)
                    .foregroundStyle(AttuneTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("When a theme keeps returning, Attune may suggest one small, editable next step. Nothing is added without your tap.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(AttuneTheme.accent)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Think out loud about a decision.")
                Text("Brain dump everything on your mind.")
                Text("Talk through your day.")
            }
            .font(.footnote)
            .foregroundStyle(AttuneTheme.textSecondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Ideas for using Talk it out: Think out loud about a decision. Brain dump everything on your mind. Talk through your day.")

            if let startErrorMessage {
                Label(startErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(AttuneTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: startListeningSession) {
                if isCheckingAIUsage {
                    ProgressView()
                        .tint(.white)
                } else {
                    Label("Start talking", systemImage: "record.circle")
                }
            }
            .buttonStyle(AttunePrimaryButtonStyle())
            .disabled(isCheckingAIUsage)
            .accessibilityHint("Starts recording so Attune can organize captured ideas and themes")
        }
    }

    private var recordingContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(AttuneTheme.recording)
                    .frame(width: 11, height: 11)
                    .shadow(color: AttuneTheme.recording.opacity(0.75), radius: 7)
                    .accessibilityHidden(true)
                Text("You’re talking it out")
                    .font(.headline)
                    .foregroundStyle(AttuneTheme.textPrimary)
                Spacer()
                Text(formattedDuration)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(AttuneTheme.textPrimary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("You’re talking it out")
            .accessibilityValue(formattedDuration)

            Text("Keep talking naturally. Repeated ideas are grouped into recurring themes in Insights.")
                .font(.subheadline)
                .foregroundStyle(AttuneTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: stopListeningSession) {
                Label("Finish", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(AttuneTheme.recording, in: RoundedRectangle(cornerRadius: AttuneTheme.controlRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Stops recording and begins processing the captured audio")
        }
        .padding(14)
        .background(AttuneTheme.recording.opacity(0.10), in: RoundedRectangle(cornerRadius: AttuneTheme.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AttuneTheme.controlRadius, style: .continuous).stroke(AttuneTheme.recording.opacity(0.35)))
    }

    private var processingContent: some View {
        statusPanel(
            icon: "sparkles",
            title: "Organizing what you said…",
            detail: "Attune is transcribing and grouping captured intentions and themes.",
            color: AttuneTheme.accentSecondary,
            showsProgress: true
        )
    }

    private var permissionRequestContent: some View {
        statusPanel(
            icon: "mic.badge.plus",
            title: "Getting ready…",
            detail: "Waiting for microphone and speech access.",
            color: AttuneTheme.accent,
            showsProgress: true
        )
    }

    private var permissionDeniedContent: some View {
        VStack(spacing: 12) {
            statusPanel(
                icon: "mic.slash.fill",
                title: "Recording access is off",
                detail: "Allow Microphone and Speech Recognition in Settings to use Talk it out.",
                color: AttuneTheme.warning
            )
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(AttunePrimaryButtonStyle())
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AttuneTheme.textPrimary)
                Spacer()
                HStack(spacing: 4) {
                    Text("\(todaySessionsCount) \(todaySessionsCount == 1 ? "session" : "sessions")")
                    Text("·")
                    Text("\(todayInsightsCount) captured")
                }
                    .font(.caption)
                    .fontWeight(showsRecentSessionCompletion ? .semibold : .regular)
                    .foregroundStyle(showsRecentSessionCompletion ? AttuneTheme.success : AttuneTheme.textSecondary)
            }

            HStack(spacing: 10) {
                historyButton(
                    title: "Past sessions",
                    icon: "waveform",
                    isHighlighted: showsRecentSessionCompletion,
                    action: { showSessionsSheet = true }
                )
                historyButton(
                    title: "Insights",
                    icon: "sparkles",
                    badgeText: recentInsightsAddedCount > 0 ? "+\(recentInsightsAddedCount) new" : nil,
                    isHighlighted: showsRecentSessionCompletion,
                    action: { showInsightsSheet = true }
                )
            }
        }
        .padding(14)
        .attuneCard()
        .overlay(
            RoundedRectangle(cornerRadius: AttuneTheme.cardRadius, style: .continuous)
                .stroke(
                    showsRecentSessionCompletion ? AttuneTheme.success.opacity(0.72) : Color.clear,
                    lineWidth: 1.5
                )
        )
        .shadow(
            color: showsRecentSessionCompletion ? AttuneTheme.success.opacity(0.22) : .clear,
            radius: 12
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: showsRecentSessionCompletion)
    }

    private func historyButton(
        title: String,
        icon: String,
        badgeText: String? = nil,
        isHighlighted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                if let badgeText {
                    Text(badgeText)
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AttuneTheme.success.opacity(0.22), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(
                isHighlighted ? AttuneTheme.success.opacity(0.15) : AttuneTheme.surfaceStrong,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isHighlighted ? AttuneTheme.success.opacity(0.60) : AttuneTheme.border)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHighlighted ? AttuneTheme.success : AttuneTheme.textPrimary)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: isHighlighted)
    }

    private func statusPanel(
        icon: String,
        title: String,
        detail: String,
        color: Color,
        showsProgress: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.16))
                    .frame(width: 42, height: 42)
                if showsProgress {
                    SwiftUI.ProgressView().tint(color)
                } else {
                    Image(systemName: icon).foregroundStyle(color)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AttuneTheme.textPrimary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AttuneTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: AttuneTheme.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AttuneTheme.controlRadius, style: .continuous).stroke(color.opacity(0.26)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(detail)
    }

    private var formattedDuration: String {
        let hours = recorder.elapsedSec / 3600
        let minutes = (recorder.elapsedSec % 3600) / 60
        let seconds = recorder.elapsedSec % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func startListeningSession() {
        guard subscriptionManager.canUseAllDayRecording else {
            showPaywall = true
            return
        }

        startErrorMessage = nil
        isCheckingAIUsage = true
        Task { @MainActor in
            defer { isCheckingAIUsage = false }
            do {
                let status = try await OpenAIClient.usageStatus()
                guard !status.limited else { return }
                requestRecordingPermissionIfNeeded()
            } catch let error as OpenAIClientError {
                startErrorMessage = error.errorDescription
            } catch {
                startErrorMessage = "Couldn’t check AI availability. Check your connection and try again."
            }
        }
    }

    private func requestRecordingPermissionIfNeeded() {
        switch PermissionsHelper.recordingPermissionState {
        case .ready:
            beginRecording()
        case .denied:
            break // Dedicated permission state provides the useful Open Settings action.
        case .needsRequest:
            isRequestingPermission = true
            Task { @MainActor in
                let granted = await PermissionsHelper.requestRecordingPermissions()
                isRequestingPermission = false
                if granted {
                    beginRecording()
                }
            }
        }
    }

    private func beginRecording() {
        recorder.startRecording()
        guard recorder.isRecording, let sessionId = recorder.currentSessionId else {
            startErrorMessage = "Couldn’t start listening. Check your audio settings and try again."
            return
        }

        activeSessionId = sessionId
        processingSessionId = nil
        isProcessing = false
        showsRecentSessionCompletion = false
        recentInsightsAddedCount = 0
        loadTodayCounts()
    }

    private func stopListeningSession() {
        guard recorder.isRecording else { return }
        processingSessionId = recorder.currentSessionId
        isProcessing = true
        startErrorMessage = nil
        recorder.stopRecording()
        loadTodayCounts()
    }

    private func recorderStateChanged(wasRecording: Bool, isRecording: Bool) {
        if isRecording {
            activeSessionId = recorder.currentSessionId
            loadTodayCounts()
            return
        }

        guard wasRecording, let sessionId = activeSessionId ?? processingSessionId else { return }
        processingSessionId = sessionId
        isProcessing = true

        activeSessionId = nil
        loadTodayCounts()
    }

    private func restoreProcessingStateIfNeeded() {
        guard !recorder.isRecording else {
            activeSessionId = recorder.currentSessionId
            return
        }

        let sessions = SessionStore.shared.loadAllSessions()
        if let session = sessions.first(where: { $0.status == "processing" || $0.status == "stopping" }) {
            processingSessionId = session.id
            isProcessing = true
        }
    }

    private func checkProcessingStatus() {
        guard !recorder.isRecording else { return }

        if processingSessionId == nil {
            let sessions = SessionStore.shared.loadAllSessions()
            processingSessionId = sessions.first(where: { $0.status == "processing" || $0.status == "stopping" })?.id
        }

        guard let sessionId = processingSessionId,
              let session = SessionStore.shared.loadSession(id: sessionId) else {
            isProcessing = transcriptionQueue.isRunning || transcriptionQueue.pendingCount > 0
            return
        }

        let hasPendingTranscription = session.segments.contains { $0.status == "queued" || $0.status == "transcribing" || $0.status == "writing" }
        let hasPendingExtraction = extractionQueue.hasPendingWork(for: sessionId)
        if session.status == "processing" || session.status == "stopping" || hasPendingTranscription || hasPendingExtraction {
            isProcessing = true
            return
        }

        isProcessing = false
        processingSessionId = nil
        loadTodayCounts()
        showCompletionFeedback(for: sessionId)
    }

    private func startProcessingCheck() {
        checkProcessingStatus()
        processingCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            checkProcessingStatus()
        }
    }

    private func loadTodayCounts() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }

        let sessions = SessionStore.shared.loadAllSessions()
        todaySessionsCount = sessions.filter { $0.startedAt >= startOfDay && $0.startedAt < endOfDay }.count

        let items = ExtractionStore.shared.loadAllExtractions()
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.formatOptions = [.withInternetDateTime]
        todayInsightsCount = items.filter { item in
            let date = fractionalFormatter.date(from: item.createdAt) ?? plainFormatter.date(from: item.createdAt)
            guard let date else { return false }
            return date >= startOfDay && date < endOfDay
        }.count
    }

    /// Displays completion feedback only after this session's transcription and captures are saved.
    private func showCompletionFeedback(for sessionId: String) {
        recentInsightsAddedCount = ExtractionStore.shared.loadExtractions(sessionId: sessionId).count
        NotificationCenter.default.post(
            name: .attuneListeningSessionDidFinishProcessing,
            object: nil,
            userInfo: ["sessionId": sessionId]
        )
        if SessionRecapFeature.isEnabled {
            showRecapPreview(for: sessionId)
        }
        let token = UUID()
        completionFeedbackToken = token
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            showsRecentSessionCompletion = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard completionFeedbackToken == token else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.55)) {
                showsRecentSessionCompletion = false
            }
            recentInsightsAddedCount = 0
        }
    }

    private func showRecapPreview(for sessionId: String) {
        guard let session = SessionStore.shared.loadSession(id: sessionId) else { return }

        let captures = ExtractionStore.shared.loadExtractions(sessionId: sessionId)
        let recap = SessionRecapBuilder.makeRecap(
            currentSession: session,
            currentItems: captures,
            allSessions: SessionStore.shared.loadAllSessions(),
            allItems: ExtractionStore.shared.loadAllExtractions(),
            topics: SessionRecapTopicSnapshotReader.load(),
            corrections: CorrectionsStore.shared.loadCorrections()
        )
        let token = UUID()
        recapPreviewToken = token

        withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)) {
            recapPreview = (sessionId, recap)
        }

        // Keep transient content available while VoiceOver is reading it.
        guard !UIAccessibility.isVoiceOverRunning else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard recapPreviewToken == token else { return }
            dismissRecapPreview()
        }
    }

    private func openRecapDetails(sessionId: String) {
        dismissRecapPreview()
        recapDetailSessionId = sessionId
    }

    private func dismissRecapPreview() {
        recapPreviewToken = UUID()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.38)) {
            recapPreview = nil
        }
    }

    private func reviewSuggestionFromTalk(_ suggestion: SuggestedIntentionAction) {
        suggestionToastCenter.dismissTalkSuggestion(id: suggestion.id)
        appRouter.selectedRootTab = .home
        Task { @MainActor in
            await Task.yield()
            NotificationCenter.default.post(
                name: .attuneReviewIntentionSuggestion,
                object: suggestion
            )
        }
    }

    private func declineSuggestionFromTalk(_ suggestion: SuggestedIntentionAction) {
        do {
            try IntentionSuggestionStore.shared.decide(.declined, suggestion: suggestion)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.34)) {
                suggestionToastCenter.resolveSuggestion(id: suggestion.id)
            }
            NotificationCenter.default.post(
                name: .attuneIntentionSuggestionDidResolve,
                object: suggestion.id
            )
        } catch {
            AppLogger.log(AppLogger.ERR, "Suggestion decline failed error=\"\(error.localizedDescription)\"")
        }
    }

    private func autoDismissTalkSuggestion(_ suggestion: SuggestedIntentionAction) async {
        guard !UIAccessibility.isVoiceOverRunning else { return }
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.78)) {
            suggestionToastCenter.dismissTalkSuggestion(id: suggestion.id)
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
}

#Preview {
    HomeRecordView()
        .environmentObject(SubscriptionManager.shared)
}
