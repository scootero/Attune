//
//  AdjustTotalSheet.swift
//  Attune
//
//  Slice 7: Sheet to set a manual override for an intention's total on a date.
//  Override takes precedence over computed total from entries.
//

import SwiftUI

/// Slice 7: Sheet for entering manual progress override amount.
struct AdjustTotalSheet: View {
    let intention: Intention
    let dateKey: String
    let currentTotal: Double
    let onSave: (Double) -> Void
    let onCancel: () -> Void
    
    /// User-editable amount string (for TextField)
    @State private var amountText: String = ""
    /// Parsed value; nil if invalid
    @FocusState private var isAmountFocused: Bool
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Current total: \(currentTotal.formatted(.number.precision(.fractionLength(1)))) \(intention.unit)")
                        .foregroundColor(.secondary)
                } header: {
                    Text(intention.title)
                }
                Section {
                    TextField("New total (\(intention.unit))", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($isAmountFocused)
                } header: {
                    Text("Override amount")
                } footer: {
                    Text("This replaces the computed total from entries for this day.")
                }
            }
            .navigationTitle("Adjust Total")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let amount = parseAmount(amountText) {
                            onSave(amount)
                        }
                    }
                    .disabled(parseAmount(amountText) == nil)
                }
            }
            .onAppear {
                amountText = currentTotal.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(currentTotal))"
                    : String(format: "%.1f", currentTotal)
                isAmountFocused = true
            }
        }
    }
    
    /// Parses amount string; returns nil if empty or invalid
    private func parseAmount(_ s: String) -> Double? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Double(trimmed), value >= 0 else { return nil }
        return value
    }
}
