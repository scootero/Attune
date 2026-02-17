//
//  MomentumChartView.swift
//  Attune
//
//  Chart card for Momentum detail page: bars showing % accomplished per intention
//  at check-in times. Uses Swift Charts. Bars at same time overlap with small offsets.
//

import SwiftUI
import Charts

/// Chart view: X = time of day, Y = % accomplished. Supports >100% with expanded axis.
struct MomentumChartView: View {

    /// Data points for the selected day
    let points: [MomentumPoint]

    /// Y-axis max (100 or 150 when any point exceeds 100%)
    let yAxisMax: Double

    /// Selected date (start of day local) for X-axis domain 00:00–23:59
    let selectedDate: Date

    /// Unique intentions for legend (deduplicated by intentionId)
    private var uniqueIntentions: [(id: String, title: String, colorIndex: Int)] {
        var seen = Set<String>()
        return points.compactMap { point -> (String, String, Int)? in
            guard !seen.contains(point.intentionId) else { return nil }
            seen.insert(point.intentionId)
            return (point.intentionId, point.intentionTitle, point.colorIndex)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Chart area
            if points.isEmpty {
                // Empty state when no check-ins or no progress
                emptyChartView
            } else {
                chartContent
            }

            // Legend: intention name → color
            if !uniqueIntentions.isEmpty {
                legendView
            }
        }
        .padding(16)
        .glassCard()
    }

    /// Chart with BarMarks; x = time (with offset), y = percent
    private var chartContent: some View {
        Chart {
            ForEach(points) { point in
                // Apply time offset so overlapping bars at same check-in shift slightly
                let displayDate = point.date.addingTimeInterval(point.timeOffsetSeconds)
                BarMark(
                    x: .value("Time", displayDate, unit: .minute),
                    y: .value("Percent", min(point.percent, yAxisMax))
                )
                .foregroundStyle(MomentumPalette.color(forIndex: point.colorIndex))
                .cornerRadius(4)
            }
        }
        .chartXScale(domain: dayStart...dayEnd)
        .chartYScale(domain: 0...yAxisMax)
        .chartXAxis {
            // Ticks every 2–3 hours
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            AxisMarks(values: .stride(by: 50)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))%")
                    }
                }
            }
        }
        .frame(height: 220)
    }

    /// Start of selected day (00:00 local)
    private var dayStart: Date {
        Calendar.current.startOfDay(for: selectedDate)
    }

    /// End of selected day (23:59:59 local)
    private var dayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: dayStart)?.addingTimeInterval(-1) ?? dayStart
    }

    /// Empty state when no momentum data for the selected day
    private var emptyChartView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.plain")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.6))
            Text("No momentum data for this day")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Record a check-in to see progress over time")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
    }

    /// Legend row: colored dot + intention name. Horizontal scroll if many.
    private var legendView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(uniqueIntentions, id: \.id) { item in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(MomentumPalette.color(forIndex: item.colorIndex))
                            .frame(width: 10, height: 10)
                        Text(item.title)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    MomentumChartView(
        points: [],
        yAxisMax: 100,
        selectedDate: Date()
    )
    .padding()
}
