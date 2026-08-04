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
                    VStack(spacing: 16) {
                        // Prefer the installed app icon when available; fall back to SF Symbol.
                        appIconView
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        Text("Attune")
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        Text("Version \(versionString) (\(buildString))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("Made by Scott")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 12)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section("Legal") {
                Link("Privacy Policy", destination: LegalLinks.privacyPolicy)
                Link("Terms of Use", destination: LegalLinks.termsOfUse)
                Link("Support", destination: LegalLinks.support)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
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
