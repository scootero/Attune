//
//  SettingsView.swift
//  Pondera
//
//  Consumer settings organized around membership, reminders, privacy/data, and support.
//

import SwiftUI
import StoreKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    // State for showing share sheet when exporting data
    @State private var showingExportSheet = false
    @State private var exportURL: URL?
    @State private var showingExportError = false
    @State private var exportErrorMessage = ""
    @State private var isReminderEnabled = ReminderPreferences.isReminderEnabled // Bind toggle to persisted enabled flag so user can turn daily reminders on/off.
    @State private var areCalendarEventRemindersEnabled = ReminderPreferences.areCalendarEventRemindersEnabled
    @State private var reminderTime = ReminderPreferences.reminderTimeDate // Bind DatePicker to persisted reminder time so user can customize notification time.
    @State private var showPaywall = false
    @State private var paywallReason: String?
    @State private var showManageSubscriptions = false
    @State private var showOnboardingReplay = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var premiumIconIsGlowing = false
    @State private var premiumTitleIsGlinting = false
    #if DEBUG && targetEnvironment(simulator)
    @State private var momentumDemoStatus = MomentumDemoDataManager.status()
    @State private var momentumDemoMessage: String?
    @State private var isChangingMomentumDemoData = false
    #endif
    
    var body: some View {
        NavigationStack {
            List {
                membershipSection
                notificationSection
                privacyAndDataSection
                supportSection
                developerSection
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(PonderaScreenBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                isReminderEnabled = ReminderPreferences.isReminderEnabled
                areCalendarEventRemindersEnabled = ReminderPreferences.areCalendarEventRemindersEnabled
                reminderTime = ReminderPreferences.reminderTimeDate
                #if DEBUG && targetEnvironment(simulator)
                refreshMomentumDemoStatus()
                #endif
            }
            .sheet(isPresented: $showingExportSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(reason: paywallReason)
                    .environmentObject(subscriptionManager)
            }
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
            .fullScreenCover(isPresented: $showOnboardingReplay) {
                OnboardingView(finalButtonTitle: "Done") {
                    showOnboardingReplay = false
                }
                .interactiveDismissDisabled(true)
            }
            .alert("Export Failed", isPresented: $showingExportError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(exportErrorMessage)
            }
            .task {
                await subscriptionManager.refresh()
            }
        }
    }

    private var membershipSection: some View {
        Section {
            VStack(spacing: 16) {
                VStack(spacing: 14) {
                    Button {
                        paywallReason = nil
                        showPaywall = true
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: "crown.fill")
                                .font(.headline)
                                .foregroundStyle(PonderaTheme.warning)
                                .frame(width: 42, height: 42)
                                .background(PonderaTheme.warning.opacity(0.16), in: Circle())
                                .scaleEffect(premiumIconIsGlowing ? 1.06 : 1)
                                .opacity(premiumIconIsGlowing ? 0.88 : 1)
                            Text(SubscriptionConfig.displayName)
                                .font(.system(size: 27, weight: .black, design: .rounded))
                                .foregroundStyle(PonderaTheme.brandGradient)
                                .opacity(premiumTitleIsGlinting ? 0.82 : 1)
                                .brightness(premiumTitleIsGlinting ? 0.12 : 0)
                                .shadow(color: PonderaTheme.accent.opacity(0.38), radius: premiumTitleIsGlinting ? 8 : 3)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)

                    Text("Everything beyond Basic — talk longer, track more, and see the full picture.")
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(PonderaTheme.textPrimary)
                        .frame(maxWidth: .infinity)

                    Button("Find Out More") {
                        paywallReason = nil
                        showPaywall = true
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PonderaTheme.accent)
                    .underline()
                    .padding(.top, 2)

                    Text("\(subscriptionManager.priceText). Cancel anytime.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PonderaTheme.textSecondary)

                    Button("Continue") {
                        paywallReason = nil
                        showPaywall = true
                    }
                    .buttonStyle(PonderaPrimaryButtonStyle())
                    .overlay(
                        RoundedRectangle(cornerRadius: PonderaTheme.controlRadius, style: .continuous)
                            .stroke(PonderaTheme.accent.opacity(0.9), lineWidth: 1.5)
                    )
                    .shadow(color: PonderaTheme.accent.opacity(0.42), radius: 14, y: 6)
                }
                .padding(16)
                .background(PonderaTheme.backgroundGradient, in: RoundedRectangle(cornerRadius: PonderaTheme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PonderaTheme.cardRadius, style: .continuous)
                        .stroke(PonderaTheme.brandGradient, lineWidth: 1.5)
                        .shadow(color: PonderaTheme.accent.opacity(0.55), radius: 8)
                )
                .shadow(color: PonderaTheme.accentSecondary.opacity(0.22), radius: 14, y: 6)

                VStack(spacing: 12) {
                    Button {
                        Task { await subscriptionManager.restore() }
                    } label: {
                        settingsLabel("Restore Purchases", icon: "arrow.clockwise", color: PonderaTheme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(subscriptionManager.isBusy)

                    Divider().overlay(PonderaTheme.border)

                    Button { showManageSubscriptions = true } label: {
                        settingsLabel("Manage Subscription", icon: "person.crop.circle", color: PonderaTheme.accentSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let message = subscriptionManager.actionState.message {
                        Label(
                            message,
                            systemImage: subscriptionManager.actionState.isFailure
                                ? "exclamationmark.triangle.fill"
                                : "info.circle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(subscriptionManager.actionState.isFailure ? PonderaTheme.warning : Color.secondary)
                    }
                }
                .padding(16)
                .background(PonderaTheme.backgroundGradient, in: RoundedRectangle(cornerRadius: PonderaTheme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PonderaTheme.cardRadius, style: .continuous)
                        .stroke(PonderaTheme.border, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.20), radius: 10, y: 5)
            }
            .onAppear {
                guard !reduceMotion else {
                    premiumTitleIsGlinting = false
                    return
                }
                withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                    premiumIconIsGlowing = true
                }
                withAnimation(.easeInOut(duration: 2.2).delay(0.4).repeatForever(autoreverses: true)) {
                    premiumTitleIsGlinting = true
                }
            }
        } header: {
            Text("Membership")
        } footer: {
            Text("Free includes one active intention, one Voice Check-In per day, today's Momentum, and the daily reminder. Pondera Pro adds more active intentions and Talk it out for \(subscriptionManager.priceText).")
        }
    }

    private var notificationSection: some View {
        Section {
            Toggle("Daily Progress Reminder", isOn: $isReminderEnabled)
                .onChange(of: isReminderEnabled) { _, newValue in
                    ReminderPreferences.isReminderEnabled = newValue
                    if newValue {
                        Task {
                            _ = await PermissionsHelper.requestNotificationPermissions()
                            DailyReminderNotificationService.shared.refreshReminderForToday()
                            CalendarEventNotificationService.shared.refresh()
                        }
                    } else {
                        DailyReminderNotificationService.shared.refreshReminderForToday()
                    }
                }

            Toggle("Calendar Event Reminders", isOn: $areCalendarEventRemindersEnabled)
                .onChange(of: areCalendarEventRemindersEnabled) { _, newValue in
                    ReminderPreferences.areCalendarEventRemindersEnabled = newValue
                    if newValue {
                        Task {
                            _ = await PermissionsHelper.requestNotificationPermissions()
                            CalendarEventNotificationService.shared.refresh()
                        }
                    } else {
                        CalendarEventNotificationService.shared.refresh()
                    }
                }

            DatePicker("Reminder Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                .disabled(!isReminderEnabled)
                .onChange(of: reminderTime) { _, newValue in
                    ReminderPreferences.reminderTimeDate = newValue
                    DailyReminderNotificationService.shared.refreshReminderForToday()
                }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Timed event captures receive alerts one hour before and when they start. Alerts use sound and the iPhone's notification vibration settings. Daily reminders remain controlled by the option above.")
        }
    }

    private var privacyAndDataSection: some View {
        Section {
            NavigationLink(destination: PrivacyDataView()) {
                settingsLabel("Permissions & Privacy", icon: "hand.raised.fill", color: PonderaTheme.accentSecondary)
            }

            Button(action: handleExportTap) {
                HStack {
                    settingsLabel("Export My Data", icon: "square.and.arrow.up", color: PonderaTheme.warning)
                    Spacer()
                    if !subscriptionManager.canExportData {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(PonderaTheme.warning)
                    }
                }
            }
        } header: {
            Text("Privacy & Data")
        } footer: {
            Text("Pondera Pro can export a portable copy of the data in your app folder for backup or personal records.")
        }
    }

    private var supportSection: some View {
        Section("Support") {
            Button {
                PonderaHaptics.selection()
                showOnboardingReplay = true
            } label: {
                settingsLabel("How Pondera Works", icon: "book.pages.fill", color: PonderaTheme.accent)
            }
            .buttonStyle(.plain)

            NavigationLink(destination: AboutView()) {
                settingsLabel("About Pondera", icon: "info.circle.fill", color: .blue)
            }
            Link(destination: LegalLinks.support) {
                settingsLabel("Help & Support", icon: "questionmark.circle.fill", color: PonderaTheme.accent)
            }
            Link(destination: LegalLinks.privacyPolicy) {
                settingsLabel("Privacy Policy", icon: "lock.shield.fill", color: PonderaTheme.accentSecondary)
            }
            Link(destination: LegalLinks.termsOfUse) {
                settingsLabel("Terms of Use", icon: "doc.text.fill", color: PonderaTheme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var developerSection: some View {
        #if DEBUG
        Section {
            Picker("Subscription Access", selection: $subscriptionManager.debugMode) {
                ForEach(DebugSubscriptionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            NavigationLink(destination: LogsView()) {
                settingsLabel("Logs", icon: "doc.text.magnifyingglass", color: .green)
            }

            NavigationLink(destination: EngagementDiagnosticsView()) {
                settingsLabel("Engagement Diagnostics", icon: "chart.bar.doc.horizontal", color: PonderaTheme.accent)
            }

            #if targetEnvironment(simulator)
            // MOMENTUM DEMO CLEANUP HANDOFF:
            // These controls reuse real intentions but create only ATTUNE_DEMO_*
            // IntentionSet/CheckIn/ProgressEntry files plus one manifest.
            // Never remove this UI by itself. First run "Remove and Verify",
            // confirm 0 records remain, and preserve the non-Debug residue cleanup
            // in PonderaApp/MomentumDemoDataManager. Full contract is documented at
            // the top of MomentumDemoDataManager.swift.
            Button {
                loadMomentumDemoData()
            } label: {
                Label("Load Momentum Demo Data", systemImage: "chart.bar.xaxis")
            }
            .disabled(isChangingMomentumDemoData || momentumDemoStatus.hasDemoData)

            Button(role: .destructive) {
                removeMomentumDemoData()
            } label: {
                Label("Remove and Verify Demo Data", systemImage: "trash")
            }
            .disabled(isChangingMomentumDemoData || !momentumDemoStatus.hasDemoData)

            if isChangingMomentumDemoData {
                HStack(spacing: 10) {
                    SwiftUI.ProgressView()
                    Text("Updating simulator data…")
                        .foregroundStyle(.secondary)
                }
            } else {
                Label(
                    momentumDemoMessage ?? momentumDemoStatus.message,
                    systemImage: momentumDemoStatus.hasDemoData ? "checkmark.circle.fill" : "circle.dashed"
                )
                .font(.caption)
                .foregroundStyle(momentumDemoStatus.hasDemoData ? Color.orange : Color.secondary)
            }
            #endif
        } header: {
            Text("Developer")
        } footer: {
            #if targetEnvironment(simulator)
            Text("Simulator only. Demo records use your existing intentions and are removed by exact manifest paths plus a reserved-ID residue scan.")
            #else
            Text("Subscription Access changes only this Debug build. Pro preserves the existing unlocked test behavior; Free verifies paywalls; System follows StoreKit.")
            #endif
        }
        #endif
    }

    private func settingsLabel(_ title: String, icon: String, color: Color) -> some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
        }
    }
    
    // MARK: - Export Function

    private func handleExportTap() {
        guard subscriptionManager.canExportData else {
            paywallReason = "Portable data export is included with Pondera Pro."
            showPaywall = true
            return
        }
        exportData()
    }
    
    /// Exports all app data by sharing the Attune data directory
    /// This allows the user to access all JSON files directly via Files app or AirDrop
    private func exportData() {
        // Get the base Attune directory which contains all data
        let baseDir = AppPaths.baseDir

        // Verify directory exists and has content
        guard FileManager.default.fileExists(atPath: baseDir.path) else {
            exportErrorMessage = "No data to export. Use Talk it out or record a Voice Check-In first."
            showingExportError = true
            return
        }

        // Share the entire Attune directory
        // iOS will let user choose how to export (Files, AirDrop, etc.)
        exportURL = baseDir
        showingExportSheet = true

        AppLogger.log(AppLogger.STORE, "Data export initiated for directory: \(baseDir.path)")
    }
    
    /// Formats a date for use in filenames (YYYY-MM-DD-HHMMSS)
    private func formatDateForFilename(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }

    #if DEBUG && targetEnvironment(simulator)
    private func refreshMomentumDemoStatus() {
        momentumDemoStatus = MomentumDemoDataManager.status()
    }

    private func loadMomentumDemoData() {
        isChangingMomentumDemoData = true
        defer { isChangingMomentumDemoData = false }
        do {
            let result = try MomentumDemoDataManager.loadUsingExistingIntentions()
            momentumDemoMessage = result.message
        } catch {
            momentumDemoMessage = error.localizedDescription
        }
        refreshMomentumDemoStatus()
    }

    private func removeMomentumDemoData() {
        isChangingMomentumDemoData = true
        defer { isChangingMomentumDemoData = false }
        do {
            let result = try MomentumDemoDataManager.removeAndVerify()
            momentumDemoMessage = result.message
        } catch {
            momentumDemoMessage = error.localizedDescription
        }
        refreshMomentumDemoStatus()
    }
    #endif
}

// MARK: - ShareSheet Helper

/// UIKit ShareSheet wrapper for SwiftUI
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

#Preview {
    SettingsView()
        .environmentObject(SubscriptionManager.shared)
}
