//
//  MomentumEmptyChartView.swift
//  Attune
//
//  Shared zero-data presentation for Momentum charts.
//

import SwiftUI

struct MomentumEmptyChartView: View {
    let period: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.6))

            Text("No momentum data for this \(period)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Record a check-in to see progress over time")
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .accessibilityElement(children: .combine)
    }
}
