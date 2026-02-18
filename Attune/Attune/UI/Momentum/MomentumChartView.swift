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
        let _ = logChartReceive() // Debug: emit chart input summary when body evaluates
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
        let debugShowTestMark = false // Debug: toggle to true to render a single hardcoded bar for isolation
        return Chart {
            ForEach(points) { point in
                // Apply time offset so overlapping bars at same check-in shift slightly
                let displayDate = point.date.addingTimeInterval(point.timeOffsetSeconds)
                BarMark(
                    x: .value("Time", displayDate, unit: .minute),
                    y: .value("Percent", min(point.percent, yAxisMax)),
                    width: .fixed(24) // Fixed width so bars are visible on 24h axis (default ~1min = nearly invisible)
                )
                .foregroundStyle(MomentumPalette.color(forIndex: point.colorIndex))
                .cornerRadius(4)
            }
            if debugShowTestMark { // Debug: hardcoded bar to validate rendering pipeline
                BarMark(
                    x: .value("Time", dayStart.addingTimeInterval(12 * 3600), unit: .minute),
                    y: .value("Percent", 50.0),
                    width: .fixed(24)
                )
                .foregroundStyle(Color.red)
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
            Image(systemName: "chart.bar") // Use valid SF Symbol to avoid runtime symbol error
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

    /// Logs a brief summary of what the chart receives so we can confirm data flow
    @discardableResult
    private func logChartReceive() -> Bool {
        let formatter = DateFormatter() // Debug: create formatter for human-readable times
        formatter.dateFormat = "HH:mm" // Debug: show hour and minute
        formatter.timeZone = TimeZone.current // Debug: use local timezone to match chart domain
        let limitedPoints = points.prefix(5) // Debug: avoid log spam by limiting to first few points
        let pointSummaries = limitedPoints.map { point in // Debug: format each point
            let timeString = formatter.string(from: point.date) // Debug: formatted time for point
            let percentString = String(format: "%.1f", point.percent) // Debug: percent with one decimal
            return "\(point.intentionTitle)@\(timeString)=\(percentString)%" // Debug: combined summary
        }
        print("[Momentum] chart receive count=\(points.count) samples=\(pointSummaries)") // Debug: emit chart input overview
        return true // Debug: allow use in let _ = logChartReceive()
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
