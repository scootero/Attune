//
//  HomeRecordView.swift
//  Attune
//
//  Consumer-facing background listening screen. RecorderService remains the
//  source of truth for session creation, background recording, and processing.
//

import SwiftUI
import UIKit

struct HomeRecordView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @StateObject private var recorder = RecorderService.shared
    @StateObject private var transcriptionQueue = TranscriptionQueue.shared
    @StateObject private var extractionQueue = ExtractionQueue.shared

    @State private var isRequestingPermission = false
    @State private var isProcessing = false
    @State private var processingSessionId: String?
    @State private var activeSessionId: String?
    @State private var startErrorMessage: String?
    @State private var processingCheckTimer: Timer?

    @State private var todaySessionsCount = 0
    @State private var todayInsightsCount = 0
    @State private var showSessionsSheet = false
    @State private var showInsightsSheet = false
    @State private var showPaywall = false

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
                    .navigationTitle("Listening Sessions")
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
            PaywallView(reason: "Background listening sessions are included with Attune Monthly.")
                .environmentObject(subscriptionManager)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Record")
                .font(.title.bold())
                .foregroundStyle(AttuneTheme.textPrimary)
            Text("Talk naturally while Attune listens and organizes what keeps coming up.")
                .font(.subheadline)
                .foregroundStyle(AttuneTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sessionHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("LISTENING SESSION", systemImage: "waveform.badge.mic")
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
                Text("Attune captures intentions, commitments, events, and recurring themes. You can leave the app or lock your phone while it listens.")
                    .font(.subheadline)
                    .foregroundStyle(AttuneTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let startErrorMessage {
                Label(startErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(AttuneTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: startListeningSession) {
                Label("Start Listening Session", systemImage: "record.circle")
            }
            .buttonStyle(AttunePrimaryButtonStyle())
            .accessibilityHint("Starts a background session that organizes captured ideas and themes")
        }
    }

    private var recordingContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(AttuneTheme.recording)
                    .frame(width: 11, height: 11)
                    .shadow(color: AttuneTheme.recording.opacity(0.75), radius: 7)
                Text("Listening in background")
                    .font(.headline)
                    .foregroundStyle(AttuneTheme.textPrimary)
                Spacer()
                Text(formattedDuration)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(AttuneTheme.textPrimary)
            }

            Text("Keep talking naturally. Repeated ideas are grouped into recurring themes in Insights.")
                .font(.subheadline)
                .foregroundStyle(AttuneTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: stopListeningSession) {
                Label("End Listening Session", systemImage: "stop.fill")
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
            title: "Organizing your session…",
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
                detail: "Allow Microphone and Speech Recognition in Settings to use listening sessions.",
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
                Text("\(todaySessionsCount) \(todaySessionsCount == 1 ? "session" : "sessions") · \(todayInsightsCount) captured")
                    .font(.caption)
                    .foregroundStyle(AttuneTheme.textSecondary)
            }

            HStack(spacing: 10) {
                historyButton(title: "Sessions", icon: "waveform", action: { showSessionsSheet = true })
                historyButton(title: "Insights", icon: "sparkles", action: { showInsightsSheet = true })
            }
        }
        .padding(14)
        .attuneCard()
    }

    private func historyButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(AttuneTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AttuneTheme.border))
        }
        .buttonStyle(.plain)
        .foregroundStyle(AttuneTheme.textPrimary)
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
}

#Preview {
    HomeRecordView()
        .environmentObject(SubscriptionManager.shared)
}
