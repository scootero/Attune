//
//  AboutView.swift
//  Attune
//
//  About screen: app identity, bundle version, and legal / support links.
//

import SwiftUI
import UIKit

struct AboutView: View {
    /// Marketing version from the Xcode target (e.g. 1.0).
    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// Build number from the Xcode target (e.g. 1).
    private var buildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        // Prefer the installed app icon when available; fall back to SF Symbol.
                        appIconView
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        Text("Pondera: Intentions")
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        Text("Version \(versionString) (\(buildString))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("Your voice, made meaningful.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)

                    }
                    .padding(.vertical, 14)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section("How Pondera Helps") {
                Text("A private, voice-first app for capturing intentions, recognizing patterns, and understanding your progress.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                aboutPoint(
                    icon: "mic.fill",
                    title: "Voice Check-Ins",
                    detail: "Update the intentions you chose and optionally record how you feel."
                )
                aboutPoint(
                    icon: "waveform.badge.mic",
                    title: "Talk it out",
                    detail: "Think out loud while Pondera captures clear intentions, commitments, events, and states from what you say."
                )
                aboutPoint(
                    icon: "sparkles",
                    title: "Insights",
                    detail: "See captured ideas and recurring themes without silently changing your tracked progress."
                )
                aboutPoint(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Momentum",
                    detail: "Review progress across a day, week, or month using your recorded check-ins."
                )
            }

            Section("Important to Know") {
                Text("Pondera records in Talk it out only after you tap Start talking. Event-like details remain reviewable captures; Pondera does not currently add calendar appointments or event reminders.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Support & Legal") {
                Link("Help & Support", destination: LegalLinks.support)
                Link("Privacy Policy", destination: LegalLinks.privacyPolicy)
                Link("Terms of Use", destination: LegalLinks.termsOfUse)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AttuneScreenBackground())
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aboutPoint(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AttuneTheme.accent)
                .frame(width: 26, height: 26)
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

    /// Loads the primary app icon from the bundle if present.
    @ViewBuilder
    private var appIconView: some View {
        if let icon = Self.bundledAppIcon() {
            Image(uiImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "waveform.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.blue)
        }
    }

    /// Reads CFBundleIcons → primary icon files from Info.plist at runtime.
    private static func bundledAppIcon() -> UIImage? {
        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let files = primary["CFBundleIconFiles"] as? [String],
            let last = files.last
        else {
            return nil
        }
        return UIImage(named: last)
    }
}

#Preview {
    NavigationView {
        AboutView()
    }
}
