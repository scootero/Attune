//
//  PrivacyDataView.swift
//  Pondera
//
//  Readable permission status and accurate local/online processing information.
//

import AVFoundation
import Speech
import SwiftUI
import UIKit
import UserNotifications

struct PrivacyDataView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var microphoneStatus = PermissionDisplayStatus.checking
    @State private var speechStatus = PermissionDisplayStatus.checking
    @State private var notificationStatus = PermissionDisplayStatus.checking

    var body: some View {
        List {
            Section {
                permissionRow(title: "Microphone", icon: "mic.fill", status: microphoneStatus)
                permissionRow(title: "Speech Recognition", icon: "waveform", status: speechStatus)
                permissionRow(title: "Notifications", icon: "bell.fill", status: notificationStatus)

                Button("Open iOS Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Pondera offers voice setup during onboarding. If you skip it, Pondera asks when you start a voice feature. Notification access is requested when you enable the daily reminder.")
            }

            Section {
                privacyPoint(
                    icon: "record.circle",
                    title: "Recording is always user-started",
                    detail: "Pondera records only after you start a Voice Check-In or tap Start talking in Talk it out."
                )
                privacyPoint(
                    icon: "text.bubble.fill",
                    title: "Voice becomes text",
                    detail: "Speech recognition may use Apple services. Transcript text may use online processing to update progress or organize Insights after you accept the disclosure."
                )
                privacyPoint(
                    icon: "calendar.badge.exclamationmark",
                    title: "Events stay suggestions",
                    detail: "Pondera can recognize event-like information for review, but it does not currently create calendar appointments or event reminders."
                )
            } header: {
                Text("How Voice Data Is Used")
            }

            Section {
                privacyPoint(
                    icon: "iphone",
                    title: "Your Pondera records",
                    detail: "Intentions, progress, sessions, captured items, themes, and available audio are stored inside Pondera’s app container on this device."
                )
                privacyPoint(
                    icon: "square.and.arrow.up",
                    title: "Portable export",
                    detail: "Use Export My Data in Settings to save a copy for backup or personal records."
                )
            } header: {
                Text("Your Data")
            } footer: {
                Text("Deleting the app can remove locally stored Pondera data. Export anything you want to keep first.")
            }

            Section("Privacy & Help") {
                Link("Read Privacy Policy", destination: LegalLinks.privacyPolicy)
                Link("Privacy or Data Request", destination: LegalLinks.support)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PonderaScreenBackground())
        .navigationTitle("Permissions & Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshStatuses() }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await refreshStatuses() }
        }
    }

    private func permissionRow(title: String, icon: String, status: PermissionDisplayStatus) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(PonderaTheme.accent)
                .frame(width: 24)
            Text(title)
            Spacer()
            Label(status.title, systemImage: status.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(status.color)
        }
        .accessibilityElement(children: .combine)
    }

    private func privacyPoint(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(PonderaTheme.accent)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }

    @MainActor
    private func refreshStatuses() async {
        microphoneStatus = PermissionDisplayStatus.microphone
        speechStatus = PermissionDisplayStatus.speech
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = PermissionDisplayStatus.notifications(settings.authorizationStatus)
    }
}

private enum PermissionDisplayStatus {
    case checking
    case allowed
    case notRequested
    case off
    case limited

    var title: String {
        switch self {
        case .checking: return "Checking"
        case .allowed: return "Allowed"
        case .notRequested: return "Not Requested"
        case .off: return "Off"
        case .limited: return "Limited"
        }
    }

    var icon: String {
        switch self {
        case .checking: return "ellipsis.circle"
        case .allowed: return "checkmark.circle.fill"
        case .notRequested: return "circle.dashed"
        case .off: return "exclamationmark.circle.fill"
        case .limited: return "minus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .checking, .notRequested: return .secondary
        case .allowed: return PonderaTheme.success
        case .off: return PonderaTheme.warning
        case .limited: return PonderaTheme.accentSecondary
        }
    }

    static var microphone: PermissionDisplayStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .allowed
        case .undetermined: return .notRequested
        case .denied: return .off
        @unknown default: return .limited
        }
    }

    static var speech: PermissionDisplayStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .allowed
        case .notDetermined: return .notRequested
        case .denied: return .off
        case .restricted: return .limited
        @unknown default: return .limited
        }
    }

    static func notifications(_ status: UNAuthorizationStatus) -> PermissionDisplayStatus {
        switch status {
        case .authorized, .provisional: return .allowed
        case .notDetermined: return .notRequested
        case .denied: return .off
        case .ephemeral: return .limited
        @unknown default: return .limited
        }
    }
}

#Preview {
    NavigationStack {
        PrivacyDataView()
    }
}
