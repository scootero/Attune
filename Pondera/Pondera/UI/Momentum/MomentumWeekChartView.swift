//
//  MomentumWeekChartView.swift
//  Pondera
//
//  End-of-day progress by intention for a selected week.
//

import SwiftUI
import Charts

struct MomentumWeekChartView: View {
    let days: [WeekDayChartData]
    let yAxisMax: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Week at a glance")
                    .font(.headline)
                    .foregroundStyle(PonderaTheme.textPrimary)
                Text("Daily totals for each intention")
                    .font(.caption)
                    .foregroundStyle(PonderaTheme.textSecondary)
            }

            if bars.isEmpty {
                emptyState
            } else {
                Chart {
                    if yAxisMax > 100 {
                        RuleMark(y: .value("Target", 100))
                            .foregroundStyle(PonderaTheme.success.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }

                    ForEach(days) { day in
                        ForEach(day.bars) { bar in
                            BarMark(
                                x: .value("Day", day.date, unit: .day),
                                y: .value("Progress", bar.percent)
                            )
                            .position(by: .value("Intention", bar.intentionId))
                            .foregroundStyle(MomentumPalette.color(forIndex: bar.colorIndex).gradient)
                            .cornerRadius(4)
                            .accessibilityLabel("\(bar.intentionTitle), \(day.date.formatted(.dateTime.weekday(.wide)))")
                            .accessibilityValue("\(Int(bar.percent.rounded())) percent")
                        }
                    }
                }
                .chartYScale(domain: 0...yAxisMax)
                .chartXAxis {
                    AxisMarks(values: days.map(\.date)) { value in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                            .foregroundStyle(PonderaTheme.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .stride(by: 25)) { value in
                        AxisGridLine().foregroundStyle(PonderaTheme.border)
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text("\(Int(number))%")
                            }
                        }
                        .foregroundStyle(PonderaTheme.textSecondary)
                    }
                }
                .frame(height: 245)
                .accessibilityLabel("Weekly progress chart")
            }
        }
        .padding(16)
        .ponderaCard()
    }

    private var bars: [WeekIntentionBar] {
        days.flatMap(\.bars)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(PonderaTheme.accent)
            Text("No recorded progress this week")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PonderaTheme.textPrimary)
            Text("Progress appears after a check-in records a numeric update.")
                .font(.caption)
                .foregroundStyle(PonderaTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 210)
        .padding(.horizontal, 20)
    }
}

#Preview {
    MomentumWeekChartView(days: [], yAxisMax: 100)
        .padding()
        .background(PonderaScreenBackground())
}
