//
//  MomentumChartView.swift
//  Attune
//
//  Daily cumulative progress chart built from check-in progress entries.
//

import SwiftUI
import Charts

struct MomentumChartView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let points: [MomentumPoint]
    let yAxisMax: Double
    let selectedDate: Date
    let hasIntentions: Bool

    @State private var selectedIntentionId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check-in progress")
                        .font(.headline)
                        .foregroundStyle(AttuneTheme.textPrimary)
                    Text("Cumulative progress when each update was recorded")
                        .font(.caption)
                        .foregroundStyle(AttuneTheme.textSecondary)
                }
                Spacer()
                if yAxisMax > 100 {
                    Text("Above target")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AttuneTheme.success)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(AttuneTheme.success.opacity(0.12), in: Capsule())
                }
            }

            if points.isEmpty {
                emptyState
            } else {
                chart
                intentionSelector
            }
        }
        .padding(16)
        .attuneCard()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: hasIntentions ? "chart.xyaxis.line" : "target")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(AttuneTheme.accent)

            Text(hasIntentions ? "No check-in progress yet" : "No tracked intentions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AttuneTheme.textPrimary)

            Text(hasIntentions
                 ? "Record a check-in with a number, such as “I finished 2 miles,” to add progress here."
                 : "Add an intention on Today, then use check-ins to record progress.")
                .font(.caption)
                .foregroundStyle(AttuneTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 210)
        .padding(.horizontal, 20)
    }

    private var chart: some View {
        Chart {
            if yAxisMax > 100 {
                RuleMark(y: .value("Target", 100))
                    .foregroundStyle(AttuneTheme.success.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Target")
                            .font(.caption2)
                            .foregroundStyle(AttuneTheme.textSecondary)
                    }
            }

            ForEach(filteredPoints) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Progress", point.percent),
                    series: .value("Intention", point.intentionId)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(MomentumPalette.color(forIndex: point.colorIndex))
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("Time", point.date),
                    y: .value("Progress", point.percent)
                )
                .foregroundStyle(MomentumPalette.color(forIndex: point.colorIndex))
                .symbol {
                    Image(systemName: MomentumIdentity.symbol(forIndex: point.colorIndex))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(MomentumPalette.color(forIndex: point.colorIndex))
                }
                .annotation(position: .top, spacing: 5) {
                    if selectedIntentionId != nil || filteredPoints.count <= 3 {
                        Text("\(Int(point.percent.rounded()))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(AttuneTheme.textSecondary)
                    }
                }
                .accessibilityLabel(point.intentionTitle)
                .accessibilityValue("\(Int(point.percent.rounded())) percent at \(point.date.formatted(.dateTime.hour().minute()))")
            }
        }
        .chartXScale(domain: dayDomain)
        .chartYScale(domain: 0...yAxisMax)
        .chartXAxis {
            AxisMarks(values: timeTicks) { value in
                AxisGridLine().foregroundStyle(AttuneTheme.border)
                AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                    .foregroundStyle(AttuneTheme.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .stride(by: 25)) { value in
                AxisGridLine().foregroundStyle(AttuneTheme.border)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text("\(Int(number))%")
                    }
                }
                .foregroundStyle(AttuneTheme.textSecondary)
            }
        }
        .frame(height: 250)
        .accessibilityLabel("Daily check-in progress chart")
    }

    private var intentionSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                selectorButton(id: nil, title: "All", colorIndex: nil)
                ForEach(legendItems, id: \.id) { item in
                    selectorButton(id: item.id, title: item.title, colorIndex: item.colorIndex)
                }
            }
        }
    }

    private func selectorButton(id: String?, title: String, colorIndex: Int?) -> some View {
        let isSelected = selectedIntentionId == id
        return Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                selectedIntentionId = id
            }
        } label: {
            HStack(spacing: 6) {
                if let colorIndex {
                    Image(systemName: MomentumIdentity.symbol(forIndex: colorIndex))
                        .font(.caption2)
                        .foregroundStyle(MomentumPalette.color(forIndex: colorIndex))
                }
                Text(title).lineLimit(1)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(isSelected ? AttuneTheme.textPrimary : AttuneTheme.textSecondary)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(isSelected ? AttuneTheme.surfaceStrong : AttuneTheme.surface, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? AttuneTheme.accent.opacity(0.7) : AttuneTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(id == nil ? "Show all intentions" : "Show \(title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var filteredPoints: [MomentumPoint] {
        guard let selectedIntentionId else { return points }
        return points.filter { $0.intentionId == selectedIntentionId }
    }

    private var legendItems: [(id: String, title: String, colorIndex: Int)] {
        var seen = Set<String>()
        return points.compactMap { point in
            guard seen.insert(point.intentionId).inserted else { return nil }
            return (point.intentionId, point.intentionTitle, point.colorIndex)
        }
    }

    private var dayDomain: ClosedRange<Date> {
        let start = Calendar.current.startOfDay(for: selectedDate)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-1) ?? start
        return start...end
    }

    private var timeTicks: [Date] {
        let start = dayDomain.lowerBound
        return [6, 12, 18].compactMap { hour in
            Calendar.current.date(byAdding: .hour, value: hour, to: start)
        }
    }
}

#Preview {
    MomentumChartView(points: [], yAxisMax: 100, selectedDate: Date(), hasIntentions: true)
        .padding()
        .background(AttuneScreenBackground())
}
