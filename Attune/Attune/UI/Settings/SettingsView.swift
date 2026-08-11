//
//  SettingsView.swift
//  Attune
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
    @State private var reminderTime = ReminderPreferences.reminderTimeDate // Bind DatePicker to persisted reminder time so user can customize notification time.
    @State private var showPaywall = false
    @State private var paywallReason: String?
    @State private var showManageSubscriptions = false
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
            .scrollContentBackground(.hidden)
            .background(AttuneScreenBackground())
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                isReminderEnabled = ReminderPreferences.isReminderEnabled
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
            Button {
                paywallReason = nil
                showPaywall = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "crown.fill")
                        .font(.headline)
                        .foregroundStyle(AttuneTheme.warning)
                        .frame(width: 36, height: 36)
                        .background(AttuneTheme.warning.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(SubscriptionConfig.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(membershipDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(subscriptionManager.isSubscribed ? "Active" : "View")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AttuneTheme.accent)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            Button {
                Task { await subscriptionManager.restore() }
            } label: {
                settingsLabel("Restore Purchases", icon: "arrow.clockwise", color: AttuneTheme.accent)
            }
            .disabled(subscriptionManager.isBusy)

            Button { showManageSubscriptions = true } label: {
                settingsLabel("Manage Subscription", icon: "person.crop.circle", color: AttuneTheme.accentSecondary)
            }

            if let message = subscriptionManager.actionState.message {
                Label(
                    message,
                    systemImage: subscriptionManager.actionState.isFailure
                        ? "exclamationmark.triangle.fill"
                        : "info.circle.fill"
                )
                .font(.footnote)
                .foregroundStyle(subscriptionManager.actionState.isFailure ? AttuneTheme.warning : Color.secondary)
            }
        } header: {
            Text("Membership")
        } footer: {
            Text("Free includes one active intention, one Voice Check-In per day, today's Momentum, and the daily reminder. Attune Pro adds more active intentions and Talk it out for \(subscriptionManager.priceText).")
        }
    }

    private var notificationSection: some View {
        Section {
            Toggle("Daily Progress Reminder", isOn: $isReminderEnabled)
                .onChange(of: isReminderEnabled) { _, newValue in
                    ReminderPreferences.isReminderEnabled = newValue
                    if newValue {
                        PermissionsHelper.requestNotificationPermissionsIfNeeded()
                    }
                    DailyReminderNotificationService.shared.refreshReminderForToday()
                }

            DatePicker("Reminder Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                .disabled(!isReminderEnabled)
                .onChange(of: reminderTime) { _, newValue in
                    ReminderPreferences.reminderTimeDate = newValue
                    PermissionsHelper.requestNotificationPermissionsIfNeeded()
                    DailyReminderNotificationService.shared.refreshReminderForToday()
                }
        } header: {
            Text("Notifications")
        } footer: {
            Text("When enabled, Attune can send one neutral reminder at your chosen time when a check-in may still be useful.")
        }
    }

    private var privacyAndDataSection: some View {
        Section {
            NavigationLink(destination: PrivacyDataView()) {
                settingsLabel("Permissions & Privacy", icon: "hand.raised.fill", color: AttuneTheme.accentSecondary)
            }

            Button(action: handleExportTap) {
                HStack {
                    settingsLabel("Export My Data", icon: "square.and.arrow.up", color: AttuneTheme.warning)
                    Spacer()
                    if !subscriptionManager.canExportData {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(AttuneTheme.warning)
                    }
                }
            }
        } header: {
            Text("Privacy & Data")
        } footer: {
            Text("Attune Pro can export a portable copy of the data in your app folder for backup or personal records.")
        }
    }

    private var supportSection: some View {
        Section("Support") {
            NavigationLink(destination: AboutView()) {
                settingsLabel("About Attune", icon: "info.circle.fill", color: .blue)
            }
            Link(destination: LegalLinks.support) {
                settingsLabel("Help & Support", icon: "questionmark.circle.fill", color: AttuneTheme.accent)
            }
            Link(destination: LegalLinks.privacyPolicy) {
                settingsLabel("Privacy Policy", icon: "lock.shield.fill", color: AttuneTheme.accentSecondary)
            }
            Link(destination: LegalLinks.termsOfUse) {
                settingsLabel("Terms of Use", icon: "doc.text.fill", color: AttuneTheme.textSecondary)
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

            #if targetEnvironment(simulator)
            // MOMENTUM DEMO CLEANUP HANDOFF:
            // These controls reuse real intentions but create only ATTUNE_DEMO_*
            // IntentionSet/CheckIn/ProgressEntry files plus one manifest.
            // Never remove this UI by itself. First run "Remove and Verify",
            // confirm 0 records remain, and preserve the non-Debug residue cleanup
            // in AttuneApp/MomentumDemoDataManager. Full contract is documented at
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

    private var membershipDetail: String {
        #if DEBUG
        switch subscriptionManager.debugMode {
        case .pro: return "Debug test mode · Pro"
        case .free: return "Debug test mode · Free"
        case .system: return isSubscribedDetail
        }
        #else
        return isSubscribedDetail
        #endif
    }

    private var isSubscribedDetail: String {
        subscriptionManager.isSubscribed
            ? "Active membership · unlimited Pro features"
            : "Free plan · \(subscriptionManager.priceText)"
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
            paywallReason = "Portable data export is included with Attune Pro."
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
