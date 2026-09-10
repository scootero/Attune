//
//  SubscriptionAccessViews.swift
//  Pondera
//
//  Free-tier previews that keep paid data and controls inaccessible while
//  showing exactly what the current plan includes.
//

import SwiftUI

struct ProLockedFeatureView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    let title: String
    let detail: String
    let icon: String

    @State private var showPaywall = false

    var body: some View {
        ZStack {
            PonderaScreenBackground()

            VStack(spacing: 20) {
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(PonderaTheme.accent)
                    .frame(width: 92, height: 92)
                    .background(PonderaTheme.accent.opacity(0.13), in: Circle())

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title.bold())
                        .foregroundStyle(PonderaTheme.textPrimary)
                    Text(detail)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(PonderaTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("View Pondera Pro") { showPaywall = true }
                    .buttonStyle(PonderaPrimaryButtonStyle())

                Text("\(subscriptionManager.priceText). Cancel anytime.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(PonderaTheme.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 28)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(reason: "\(title) is included with Pondera Pro.")
                .environmentObject(subscriptionManager)
        }
    }

}

/// Free users can see only today's Momentum. Historical navigation, Week,
/// Month, and progress history remain behind Pondera Pro.
struct FreeMomentumTodayView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    @State private var points: [MomentumPoint] = []
    @State private var yAxisMax: Double = 100
    @State private var overallRatio: Double = 0
    @State private var intentionCount = 0
    @State private var checkInCount = 0
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            PonderaScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Momentum")
                            .font(.largeTitle.bold())
                            .foregroundStyle(PonderaTheme.textPrimary)
                        Text("Today's progress from your Voice Check-In.")
                            .font(.subheadline)
                            .foregroundStyle(PonderaTheme.textSecondary)
                    }

                    HStack(spacing: 0) {
                        summary(value: percentText(overallRatio), label: "overall")
                        summary(value: "\(intentionCount)", label: intentionCount == 1 ? "intention" : "intentions")
                        summary(value: "\(checkInCount)", label: checkInCount == 1 ? "check-in" : "check-ins")
                    }
                    .padding(.vertical, 14)
                    .ponderaCard()

                    MomentumChartView(
                        points: points,
                        yAxisMax: yAxisMax,
                        selectedDate: Calendar.current.startOfDay(for: Date()),
                        hasIntentions: intentionCount > 0
                    )

                    Button { showPaywall = true } label: {
                        HStack(spacing: 13) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.title3)
                                .foregroundStyle(PonderaTheme.warning)
                                .frame(width: 42, height: 42)
                                .background(PonderaTheme.warning.opacity(0.13), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Unlock your full Momentum history")
                                    .font(.headline)
                                    .foregroundStyle(PonderaTheme.textPrimary)
                                Text("See past days plus Week and Month views with Pondera Pro.")
                                    .font(.subheadline)
                                    .foregroundStyle(PonderaTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(PonderaTheme.textTertiary)
                        }
                        .padding(16)
                    }
                    .buttonStyle(.plain)
                    .ponderaCard()
                }
                .padding(.horizontal, PonderaTheme.horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 112)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear(perform: loadToday)
        .sheet(isPresented: $showPaywall) {
            PaywallView(reason: "Past days, Week and Month Momentum, and progress history are included with Pondera Pro.")
                .environmentObject(subscriptionManager)
        }
    }

    private func summary(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(PonderaTheme.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(PonderaTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func percentText(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded()))%"
    }

    private func loadToday() {
        let date = Calendar.current.startOfDay(for: Date())
        let dateKey = ProgressCalculator.dateKey(for: date)
        let detail = ProgressDataHelper.loadDayDetail(dateKey: dateKey)
        overallRatio = detail.overallPercent
        intentionCount = detail.intentions.count
        checkInCount = detail.checkIns.count

        guard let set = detail.intentionSet else {
            points = []
            yAxisMax = 100
            return
        }

        let entries = detail.entriesByIntentionId.values.flatMap { $0 }
        points = MomentumPointAdapter.buildPoints(
            dateKey: dateKey,
            intentionSet: set,
            intentions: detail.intentions,
            checkIns: detail.checkIns,
            entries: entries,
            overrides: OverrideStore.shared.loadOverrideRecordsForDate(dateKey: dateKey)
        ).map { point in
            MomentumPoint(
                id: point.id,
                date: point.date,
                intentionId: point.intentionId,
                intentionTitle: point.intentionTitle,
                colorIndex: MomentumIdentity.index(for: point.intentionId),
                recordingId: point.recordingId,
                percent: point.percent,
                timeOffsetSeconds: point.timeOffsetSeconds
            )
        }
        yAxisMax = MomentumPointAdapter.yAxisMax(for: points)
    }
}
