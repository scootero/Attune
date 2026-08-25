//
//  LegacyMomentumMonthChartView.swift
//  Pondera
//
//  Monthly daily-bar chart using the current monthly data source.
//

import SwiftUI
import Charts

/// Renders one daily bar across the selected calendar month. Missing days receive
/// only a neutral baseline marker.
struct LegacyMomentumMonthChartView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let bars: [MonthDayBar]
    @State private var barEntranceClock = 0.0

    var body: some View {
        Group {
            if hasMomentumData {
                chart
            } else {
                MomentumEmptyChartView(period: "month")
                    .padding(16)
                    .glassCard()
            }
        }
        .task(id: barAnimationIdentity) {
            await runBarEntranceAnimation()
        }
    }

    private var chart: some View {
        Chart {
            ForEach(Array(elapsedBars.enumerated()), id: \.element.id) { index, bar in
                BarMark(
                    x: .value("Day", bar.date, unit: .day),
                    y: .value(
                        "Momentum",
                        barHeight(for: bar) * MomentumBarEntranceAnimation.scale(
                            clock: barEntranceClock,
                            index: index,
                            barCount: elapsedBars.count,
                            reduceMotion: reduceMotion
                        )
                    )
                )
                .foregroundStyle(barColor(for: bar).gradient)
                .cornerRadius(4)
                .accessibilityLabel(bar.date.formatted(.dateTime.month().day()))
                .accessibilityValue(accessibilityValue(for: bar))
            }
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: monthDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                AxisGridLine().foregroundStyle(AttuneTheme.border)
                AxisValueLabel(format: .dateTime.day())
                    .foregroundStyle(AttuneTheme.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine().foregroundStyle(AttuneTheme.border)
                AxisValueLabel {
                    if let number = value.as(Int.self) {
                        Text("\(number)%")
                    }
                }
                .foregroundStyle(AttuneTheme.textSecondary)
            }
        }
        .frame(height: 220)
        .accessibilityLabel("Monthly progress chart")
        .padding(16)
        .glassCard()
    }

    private var hasMomentumData: Bool {
        elapsedBars.contains { ($0.ratio ?? 0) > 0 }
    }

    private var elapsedBars: [MonthDayBar] {
        bars.filter { !$0.isFutureDay }
    }

    private var barAnimationIdentity: String {
        let barsIdentity = elapsedBars
            .map { "\($0.id):\($0.ratio ?? -1)" }
            .joined(separator: "|")
        return "\(barsIdentity)|reduce:\(reduceMotion)"
    }

    @MainActor
    private func runBarEntranceAnimation() async {
        let duration = MomentumBarEntranceAnimation.totalDuration(barCount: elapsedBars.count)
        var resetTransaction = Transaction()
        resetTransaction.disablesAnimations = true
        withTransaction(resetTransaction) {
            barEntranceClock = reduceMotion ? duration : 0
        }

        guard !reduceMotion, !elapsedBars.isEmpty else { return }
        await Task.yield()
        guard !Task.isCancelled else { return }
        withAnimation(.linear(duration: duration)) {
            barEntranceClock = duration
        }
    }

    private var monthDomain: ClosedRange<Date> {
        let sortedDates = bars.map(\.date).sorted()
        let start = sortedDates.first ?? Date()
        let end = sortedDates.last ?? start
        return start...end
    }

    /// A tiny neutral marker keeps an elapsed day visible without representing it
    /// as recorded progress.
    private func barHeight(for bar: MonthDayBar) -> Double {
        guard let ratio = bar.ratio else { return 1.5 }
        return min(max(ratio * 100, 0), 100)
    }

    private func barColor(for bar: MonthDayBar) -> Color {
        guard bar.ratio != nil else {
            return AttuneTheme.textTertiary.opacity(0.24)
        }

        switch bar.tier {
        case .veryLow: return AttuneTheme.recording
        case .low: return AttuneTheme.warning
        case .neutral: return Color(red: 0.90, green: 0.76, blue: 0.32)
        case .good: return AttuneTheme.success
        case .great: return AttuneTheme.accent
        case nil: return AttuneTheme.textTertiary
        }
    }

    private func accessibilityValue(for bar: MonthDayBar) -> String {
        guard let ratio = bar.ratio else { return "No recorded progress" }
        return "\(Int((ratio * 100).rounded())) percent overall progress"
    }
}

#Preview {
    LegacyMomentumMonthChartView(bars: [])
        .padding()
        .background(AttuneScreenBackground())
}
