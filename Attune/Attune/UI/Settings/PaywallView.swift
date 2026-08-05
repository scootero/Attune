//
//  PaywallView.swift
//  Attune
//
//  Simple paywall for the single $5.99/month Attune subscription.
//  Subscribe + Restore Purchases (Apple requires restore).
//

import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    /// Optional short reason shown under the title (e.g. daily free limit reached).
    var reason: String? = nil

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text(SubscriptionConfig.displayName)
                    .font(.largeTitle.bold())

                if let reason = reason, !reason.isEmpty {
                    Text(reason)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                Text("Subscribe for unlimited check-ins, background listening sessions, and voice-created intentions.")
                    .font(.body)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Unlimited daily check-ins", systemImage: "checkmark.circle.fill")
                    Label("Background listening sessions", systemImage: "checkmark.circle.fill")
                    Label("Record Intentions by voice", systemImage: "checkmark.circle.fill")
                    Label("Cancel anytime in Apple Settings", systemImage: "checkmark.circle.fill")
                }
                .font(.body)

                Text(subscriptionManager.priceText)
                    .font(.title2.weight(.semibold))
                    .padding(.top, 8)

                if let error = subscriptionManager.lastErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                }

                Spacer()

                Button {
                    Task {
                        await subscriptionManager.purchase()
                        if subscriptionManager.isSubscribed {
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        if subscriptionManager.isBusy {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(subscriptionManager.isSubscribed ? "Subscribed" : "Subscribe")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(subscriptionManager.isBusy || subscriptionManager.isSubscribed)

                Button("Restore Purchases") {
                    Task {
                        await subscriptionManager.restore()
                        if subscriptionManager.isSubscribed {
                            dismiss()
                        }
                    }
                }
                .disabled(subscriptionManager.isBusy)

                // Apple requires functional Privacy + Terms of Use (EULA) links near IAP.
                HStack(spacing: 16) {
                    Link("Privacy Policy", destination: LegalLinks.privacyPolicy)
                    Link("Terms of Use", destination: LegalLinks.termsOfUse)
                    Link("Apple EULA", destination: LegalLinks.appleStandardEULA)
                }
                .font(.footnote)
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await subscriptionManager.refresh()
            }
        }
    }
}

#Preview {
    PaywallView(reason: "You’ve used your 3 free check-ins today.")
        .environmentObject(SubscriptionManager.shared)
}
