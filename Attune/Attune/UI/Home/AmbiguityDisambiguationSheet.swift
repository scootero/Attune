//
//  AmbiguityDisambiguationSheet.swift
//  Attune
//
//  Slice 7: One prompt per check-in. User disambiguates each update as
//  "Total today", "X more", or "Skip". Cancel skips all ambiguous updates.
//

import SwiftUI

/// User's choice for one ambiguous update
enum AmbiguityChoice {
    /// Treat as absolute total for the day (persist as TOTAL)
    case totalToday
    /// Treat as increment to add (persist as INCREMENT)
    case increment
    /// Skip this update (do not persist)
    case skip
}

/// Resolved ambiguous update: original update + user's choice
struct AmbiguityResolution {
    let update: CheckInUpdate
    let choice: AmbiguityChoice
}

/// Slice 7: Sheet to disambiguate updates when late-day + low confidence + material change.
/// One sheet per check-in; batches all ambiguous updates from that extraction.
struct AmbiguityDisambiguationSheet: View {
    /// Ambiguous updates from extraction (one per intention typically)
    let ambiguousUpdates: [CheckInUpdate]
    /// Intentions for display (title, unit)
    let intentions: [Intention]
    /// Called with user's resolutions; empty choice = skip. onResolve never includes .skip.
    let onResolve: ([AmbiguityResolution]) -> Void
    /// Called when user cancels (skip all ambiguous)
    let onCancel: () -> Void
    
    /// Per-update choice (index into ambiguousUpdates)
    @State private var choices: [Int: AmbiguityChoice] = [:]
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Some updates are unclear. How should we apply each?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(ambiguousUpdates.enumerated()), id: \.offset) { index, update in
                            ambiguousUpdateRow(index: index, update: update)
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer(minLength: 16)
            }
            .navigationTitle("Clarify Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let resolved = ambiguousUpdates.enumerated().compactMap { index, update -> AmbiguityResolution? in
                            guard let choice = choices[index], choice != .skip else { return nil }
                            return AmbiguityResolution(update: update, choice: choice)
                        }
                        onResolve(resolved)
                    }
                    .disabled(!allResolved)
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    /// True when every update has a choice (including Skip)
    private var allResolved: Bool {
        ambiguousUpdates.indices.allSatisfy { choices[$0] != nil }
    }
    
    private func ambiguousUpdateRow(index: Int, update: CheckInUpdate) -> some View {
        let intention = intentions.first { $0.id == update.intentionId }
        let title = intention?.title ?? "Unknown"
        let unit = intention?.unit ?? update.unit
        
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            if let evidence = update.evidence, !evidence.isEmpty {
                Text("\"\(evidence)\"")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text("\(formatAmount(update.amount)) \(unit)")
                .font(.subheadline)
            
            HStack(spacing: 8) {
                // "Total today" = treat amount as absolute total
                Button {
                    choices[index] = .totalToday
                } label: {
                    Text("Total today")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(choiceBg(for: index, is: .totalToday))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                
                // "X more" = treat as increment
                Button {
                    choices[index] = .increment
                } label: {
                    Text("\(formatAmount(update.amount)) more")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(choiceBg(for: index, is: .increment))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                
                // "Skip" = do not apply
                Button {
                    choices[index] = .skip
                } label: {
                    Text("Skip")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(choiceBg(for: index, is: .skip))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func choiceBg(for index: Int, is choice: AmbiguityChoice) -> Color {
        choices[index] == choice ? Color.accentColor.opacity(0.3) : Color.clear
    }
    
    private func formatAmount(_ n: Double) -> String {
        if n.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(n))"
        }
        return String(format: "%.1f", n)
    }
}
