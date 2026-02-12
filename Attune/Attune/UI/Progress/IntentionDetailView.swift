//
//  IntentionDetailView.swift
//  Attune
//
//  Per-goal detail: last 7 days of % complete and totals. Slice 6.
//

import SwiftUI

struct IntentionDetailView: View {
    let intention: Intention
    let intentionSet: IntentionSet
    
    @State private var data: IntentionDetailData?
    
    var body: some View {
        Group {
            if let data = data {
                intentionDetailContent(data: data)
            } else {
                SwiftUI.ProgressView()
            }
        }
        .navigationTitle(intention.title)
        .onAppear {
            data = ProgressDataHelper.loadIntentionDetail(intention: intention, intentionSet: intentionSet)
        }
    }
    
    private func intentionDetailContent(data: IntentionDetailData) -> some View {
        List {
            Section("Target") {
                HStack {
                    Text("\(Int(data.intention.targetValue)) \(data.intention.unit)/\(data.intention.timeframe)")
                        .font(.body)
                }
            }
            
            Section("Last 7 days") {
                ForEach(Array(data.dayRows.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(formatDate(row.date))
                            .font(.body)
                        Spacer()
                        Text("\(row.total.formatted(.number.precision(.fractionLength(1)))) / \(Int(data.intention.targetValue))")
                            .font(.body)
                            .foregroundColor(.secondary)
                        Text("\(Int(row.percent * 100))%")
                            .font(.body.monospacedDigit())
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
