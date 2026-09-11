//
//  PaywallView.swift
//  Pondera
//
//  Consumer Pondera Pro paywall backed by the existing monthly StoreKit product.
//

import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    /// Optional short reason shown under the title (e.g. daily free limit reached).
    var reason: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @State private var isBreathing = false

    var body: some View {
        NavigationStack {
            ZStack {
                PonderaScreenBackground()

                VStack(alignment: .leading, spacing: 10) {
                    hero

                    if let reason, !reason.isEmpty {
                        Label(reason, systemImage: "sparkles")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(PonderaTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PonderaTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: PonderaTheme.controlRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: PonderaTheme.controlRadius, style: .continuous).stroke(PonderaTheme.accent.opacity(0.28)))
                    }

                    VStack(spacing: 7) {
                        proFeature(icon: "target", title: "Track More Intentions", detail: "Keep up to \(SubscriptionConfig.maximumActiveIntentions) active intentions moving at the same time.", tint: PonderaTheme.accent)
                        proFeature(icon: "mic.fill", title: "Voice Check-Ins", detail: "Update intentions and optional mood within Pro’s included monthly AI allowance.", tint: PonderaTheme.recording)
                        proFeature(icon: "waveform.badge.mic", title: "Talk it out with Insights", detail: "Organize what’s on your mind into intentions, commitments, events, states, and themes.", tint: PonderaTheme.accentSecondary)
                        proFeature(icon: "chart.line.uptrend.xyaxis", title: "Full Momentum History", detail: "Review past days plus Week and Month views to see progress over time.", tint: PonderaTheme.warning)
                        proFeature(icon: "square.and.arrow.up", title: "Voice Setup and Data Export", detail: "Create intentions by voice with review, and export a portable copy of your Pondera data.", tint: PonderaTheme.success)
                    }

                    purchaseArea
                    legalFooter
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            .onAppear {
                hasAppeared = reduceMotion
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.55)) { hasAppeared = true }
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(PonderaTheme.accent.opacity(0.28), lineWidth: 1.5)
                    .frame(width: 72, height: 72)
                    .scaleEffect(isBreathing ? 1.14 : 0.94)
                    .opacity(isBreathing ? 0.18 : 0.72)
                Circle()
                    .stroke(PonderaTheme.accentSecondary.opacity(0.32), lineWidth: 1)
                    .frame(width: 58, height: 58)
                    .scaleEffect(isBreathing ? 0.92 : 1.08)
                    .opacity(isBreathing ? 0.7 : 0.18)
                PonderaBrandMark()
                    .frame(width: 48, height: 48)
                    .shadow(color: PonderaTheme.accent.opacity(0.44), radius: 12)
            }
            .accessibilityHidden(true)

            HStack(spacing: 8) {
                Text(SubscriptionConfig.displayName)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(PonderaTheme.brandGradient)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityAddTraits(.isHeader)

            Text("Track more, see the patterns, and keep your full progress history.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(PonderaTheme.textSecondary)
                .frame(maxWidth: .infinity)

            Text("\(subscriptionManager.priceText). Cancel anytime.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PonderaTheme.accent)
        }
        .frame(maxWidth: .infinity)
    }

    private func proFeature(icon: String, title: String, detail: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14), in: Circle())
                .scaleEffect(reduceMotion ? 1 : (isBreathing ? 1.05 : 0.97))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PonderaTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(PonderaTheme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(PonderaTheme.surface, in: RoundedRectangle(cornerRadius: PonderaTheme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PonderaTheme.controlRadius, style: .continuous)
                .stroke(tint.opacity(0.30), lineWidth: 1)
        )
        .opacity(hasAppeared || reduceMotion ? 1 : 0)
        .offset(y: hasAppeared || reduceMotion ? 0 : 7)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var purchaseArea: some View {
        VStack(spacing: 12) {
            if subscriptionManager.isSubscribed {
                Label("Pondera Pro is active", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(PonderaTheme.success)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .ponderaCard()
            } else if subscriptionManager.isLoadingProduct {
                HStack(spacing: 10) {
                    SwiftUI.ProgressView().tint(PonderaTheme.accent)
                    Text("Loading Pondera Pro…")
                        .font(.headline)
                        .foregroundStyle(PonderaTheme.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(18)
                .ponderaCard()
            } else {
                if let message = subscriptionManager.actionState.message {
                    Label(message, systemImage: subscriptionManager.actionState.isFailure ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(subscriptionManager.actionState.isFailure ? PonderaTheme.warning : PonderaTheme.textSecondary)
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
                    HStack(spacing: 10) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 17, weight: .bold))
                        VStack(spacing: 2) {
                            if subscriptionManager.isBusy {
                                SwiftUI.ProgressView().tint(Color.black)
                            }
                            Text(subscriptionManager.isProductAvailable ? "Subscribe to Pondera Pro" : "Try Again")
                                .font(.system(size: 18, weight: .black, design: .rounded))
                            if subscriptionManager.isProductAvailable {
                                Text(subscriptionManager.priceText)
                                    .font(.caption.weight(.bold))
                            }
                        }
                        Image(systemName: "crown.fill")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PonderaPrimaryButtonStyle())
                .overlay(
                    RoundedRectangle(cornerRadius: PonderaTheme.controlRadius, style: .continuous)
                        .stroke(PonderaTheme.accent.opacity(0.9), lineWidth: 1.5)
                )
                .shadow(color: PonderaTheme.accent.opacity(0.42), radius: 15, y: 6)
                .disabled(subscriptionManager.isBusy)

                if subscriptionManager.isProductAvailable {
                    Text("\(subscriptionManager.priceText), auto-renewing unless cancelled at least 24 hours before renewal.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(PonderaTheme.textSecondary)
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
            .foregroundStyle(PonderaTheme.accent)
            .frame(minHeight: 44)
            .disabled(subscriptionManager.isBusy || subscriptionManager.isLoadingProduct)
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
        .foregroundStyle(PonderaTheme.textTertiary)
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
