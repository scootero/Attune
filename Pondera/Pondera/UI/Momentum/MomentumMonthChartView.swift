//
//  MomentumMonthChartView.swift
//  Pondera
//
//  Daily overall progress for a selected month.
//

import SwiftUI
import Charts

struct MomentumMonthChartView: View {
    let bars: [MonthDayBar]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Monthly consistency")
                    .font(.headline)
                    .foregroundStyle(PonderaTheme.textPrimary)
                Text("Overall tracked progress on days with recorded updates")
                    .font(.caption)
                    .foregroundStyle(PonderaTheme.textSecondary)
            }

            if recordedBars.isEmpty {
                emptyState
            } else {
                Chart(recordedBars) { bar in
                    BarMark(
                        x: .value("Day", bar.date, unit: .day),
                        y: .value("Momentum", (bar.ratio ?? 0) * 100)
                    )
                    .foregroundStyle(color(for: bar.tier).gradient)
                    .cornerRadius(3)
                    .accessibilityLabel(bar.date.formatted(.dateTime.month().day()))
                    .accessibilityValue("\(Int(((bar.ratio ?? 0) * 100).rounded())) percent overall progress")
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 5)) { value in
                        AxisGridLine().foregroundStyle(PonderaTheme.border.opacity(0.6))
                        AxisValueLabel(format: .dateTime.day())
                            .foregroundStyle(PonderaTheme.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine().foregroundStyle(PonderaTheme.border)
                        AxisValueLabel {
                            if let number = value.as(Int.self) {
                                Text("\(number)%")
                            }
                        }
                        .foregroundStyle(PonderaTheme.textSecondary)
                    }
                }
                .frame(height: 245)
                .accessibilityLabel("Monthly progress chart")
            }
        }
        .padding(16)
        .ponderaCard()
    }

    private var recordedBars: [MonthDayBar] {
        bars.filter { $0.ratio != nil && !$0.isFutureDay }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(PonderaTheme.accent)
            Text("No recorded progress this month")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PonderaTheme.textPrimary)
            Text("Days appear here after a check-in or a manual progress adjustment.")
                .font(.caption)
                .foregroundStyle(PonderaTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 210)
        .padding(.horizontal, 20)
    }

    private func color(for tier: MomentumTier?) -> Color {
        switch tier {
        case .veryLow: return PonderaTheme.recording
        case .low: return PonderaTheme.warning
        case .neutral: return Color(red: 0.90, green: 0.76, blue: 0.32)
        case .good: return PonderaTheme.success
        case .great: return PonderaTheme.accent
        case nil: return PonderaTheme.textTertiary
        }
    }
}

#Preview {
    MomentumMonthChartView(bars: [])
        .padding()
        .background(PonderaScreenBackground())
}
