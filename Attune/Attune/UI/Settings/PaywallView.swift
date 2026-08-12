//
//  PaywallView.swift
//  Attune
//
//  Consumer Attune Pro paywall backed by the existing monthly StoreKit product.
//

import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    /// Optional short reason shown under the title (e.g. daily free limit reached).
    var reason: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                AttuneScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        hero

                        if let reason, !reason.isEmpty {
                            Label(reason, systemImage: "sparkles")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AttuneTheme.textPrimary)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AttuneTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: AttuneTheme.controlRadius, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: AttuneTheme.controlRadius, style: .continuous).stroke(AttuneTheme.accent.opacity(0.28)))
                        }

                        VStack(spacing: 12) {
                            proFeature(
                                icon: "target",
                                title: "Track More Intentions",
                                detail: "Keep up to \(SubscriptionConfig.maximumActiveIntentions) active intentions moving at the same time."
                            )
                            proFeature(
                                icon: "mic.fill",
                                title: "Voice Check-Ins",
                                detail: "Update your tracked intentions and optional mood within Pro’s included monthly AI allowance."
                            )
                            proFeature(
                                icon: "waveform.badge.mic",
                                title: "Talk it out with Insights",
                                detail: "Talk through what’s on your mind. Attune organizes clear intentions, commitments, events, and states, then groups repeated ideas into themes."
                            )
                            proFeature(
                                icon: "chart.line.uptrend.xyaxis",
                                title: "Full Momentum History",
                                detail: "Review past days and use Week and Month views to see how your progress changes over time."
                            )
                            proFeature(
                                icon: "square.and.arrow.up",
                                title: "Voice Setup and Data Export",
                                detail: "Create intentions by voice with review, and export a portable copy of your Attune data."
                            )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Attune Free")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AttuneTheme.textSecondary)
                                .textCase(.uppercase)
                                .tracking(0.8)
                            Text("Track one active intention, record one Voice Check-In per day, see today's Momentum, and use the daily progress reminder.")
                                .font(.subheadline)
                                .foregroundStyle(AttuneTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .attuneCard()

                        legalFooter
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    purchaseBar
                }
            }
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

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AttuneTheme.warning.opacity(0.14))
                    .frame(width: 82, height: 82)
                Image(systemName: "crown.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(AttuneTheme.warning)
            }
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(SubscriptionConfig.displayName)
                    .font(.largeTitle.bold())
                    .foregroundStyle(AttuneTheme.textPrimary)
                Text("Track more, see the patterns, and keep your full progress history.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AttuneTheme.textSecondary)
            }

            Text("\(subscriptionManager.priceText). Cancel anytime.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AttuneTheme.accent)
            Text("Includes a generous monthly AI processing allowance that refreshes each calendar month.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(AttuneTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func proFeature(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(AttuneTheme.accent)
                .frame(width: 40, height: 40)
                .background(AttuneTheme.accent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
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
        .padding(16)
        .attuneCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var purchaseArea: some View {
        VStack(spacing: 12) {
            if subscriptionManager.isSubscribed {
                Label("Attune Pro is active", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(AttuneTheme.success)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .attuneCard()
            } else if subscriptionManager.isLoadingProduct {
                HStack(spacing: 10) {
                    SwiftUI.ProgressView().tint(AttuneTheme.accent)
                    Text("Loading Attune Pro…")
                        .font(.headline)
                        .foregroundStyle(AttuneTheme.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(18)
                .attuneCard()
            } else {
                if let message = subscriptionManager.actionState.message {
                    Label(message, systemImage: subscriptionManager.actionState.isFailure ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(subscriptionManager.actionState.isFailure ? AttuneTheme.warning : AttuneTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    if !subscriptionManager.isProductAvailable {
                        Task { await subscriptionManager.refresh() }
                    } else {
                        Task {
                            await subscriptionManager.purchase()
                            if subscriptionManager.isSubscribed { dismiss() }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if subscriptionManager.isBusy {
                            SwiftUI.ProgressView().tint(Color(red: 0.025, green: 0.12, blue: 0.12))
                        }
                        Text(subscriptionManager.isProductAvailable ? "Subscribe to Attune Pro" : "Try Again")
                    }
                }
                .buttonStyle(AttunePrimaryButtonStyle())
                .disabled(subscriptionManager.isBusy)

                if subscriptionManager.isProductAvailable {
                    Text("\(subscriptionManager.priceText), auto-renewing unless cancelled at least 24 hours before renewal.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(AttuneTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            Button("Restore Purchases") {
                Task {
                    await subscriptionManager.restore()
                    if subscriptionManager.isSubscribed { dismiss() }
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AttuneTheme.accent)
            .frame(minHeight: 44)
            .disabled(subscriptionManager.isBusy || subscriptionManager.isLoadingProduct)
        }
    }

    private var purchaseBar: some View {
        purchaseArea
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AttuneTheme.border)
                    .frame(height: 1)
            }
    }

    private var legalFooter: some View {
        VStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    legalLinks
                }
                VStack(spacing: 0) {
                    legalLinks
                }
            }
            Text(legalPaymentText)
                .multilineTextAlignment(.center)
        }
        .font(.caption)
        .foregroundStyle(AttuneTheme.textTertiary)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var legalLinks: some View {
        Link("Privacy", destination: LegalLinks.privacyPolicy)
            .frame(minHeight: 44)
        Link("Terms", destination: LegalLinks.termsOfUse)
            .frame(minHeight: 44)
        Link("Apple EULA", destination: LegalLinks.appleStandardEULA)
            .frame(minHeight: 44)
    }

    private var legalPaymentText: String {
        "Payment is charged to your Apple ID after confirmation. Cancel anytime in Apple account settings."
    }
}

#Preview {
    PaywallView(reason: "You’ve reached today’s free Voice Check-In limit.")
        .environmentObject(SubscriptionManager.shared)
}
