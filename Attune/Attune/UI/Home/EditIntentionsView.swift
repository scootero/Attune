//
//  EditIntentionsView.swift
//  Attune
//
//  Draft editing of intentions (max 5). On Save: ends current IntentionSet,
//  creates new one with updated Intention records. Slice 5.
//

import SwiftUI

/// Editable draft of an intention (mutable for form binding)
struct DraftIntention: Identifiable {
    var id: String
    var title: String
    var targetValue: Double
    var unit: String
    var timeframe: String  // "daily" or "weekly"
    
    static let maxCount = 5
    
    static let unitOptions = ["pages", "minutes", "sessions", "steps", "reps", "cups", "glasses"]
    
    static func empty() -> DraftIntention {
        DraftIntention(
            id: UUID().uuidString,
            title: "",
            targetValue: 10,
            unit: "minutes",
            timeframe: "daily"
        )
    }
    
    func toIntention() -> Intention {
        Intention(
            id: id,
            title: title.isEmpty ? "New" : title,
            targetValue: max(0, targetValue),
            unit: unit,
            timeframe: timeframe,
            category: nil,
            isActive: true,
            createdAt: Date()
        )
    }
}

struct EditIntentionsView: View {
    @Environment(\.dismiss) private var dismiss
    
    /// Draft intentions (max 5)
    @State private var draftIntentions: [DraftIntention] = []
    /// True while loading draft from disk on background (avoids blocking main thread)
    @State private var isLoadingDraft = true
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoadingDraft {
                    // Show spinner while loading; prevents perceived freeze on sheet open
                    VStack(spacing: 8) {
                        SwiftUI.ProgressView()
                        Text("Loading...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach($draftIntentions) { $draft in
                            IntentionEditRow(draft: $draft)
                        }
                        .onDelete(perform: deleteDraft)
                        
                        if draftIntentions.count < DraftIntention.maxCount {
                            Button(action: addDraft) {
                                Label("Add Intention", systemImage: "plus.circle.fill")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Intentions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Changes") {
                        saveAndDismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                loadDraftFromCurrent()
            }
        }
    }
    
    private var canSave: Bool {
        draftIntentions.contains { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    
    private func addDraft() {
        guard draftIntentions.count < DraftIntention.maxCount else { return }
        draftIntentions.append(DraftIntention.empty())
    }
    
    private func deleteDraft(at offsets: IndexSet) {
        draftIntentions.remove(atOffsets: offsets)
    }
    
    /// Loads current intentions as draft on background queue; completion runs on main.
    /// Uses EditIntentionsDraftLoader to avoid blocking main thread during sheet open.
    /// Defers UI update to next run loop so sheet animation can complete; avoids
    /// "multiple updates per frame" and keyboard snapshot errors.
    private func loadDraftFromCurrent() {
        EditIntentionsDraftLoader.loadDraftInBackground { results in
            // Defer UI update to next run loop so sheet animation can complete;
            // avoids "multiple updates per frame" and keyboard snapshot errors.
            DispatchQueue.main.async {
                draftIntentions = results.map { r in
                    DraftIntention(
                        id: r.id,
                        title: r.title,
                        targetValue: r.targetValue,
                        unit: r.unit,
                        timeframe: r.timeframe
                    )
                }
                isLoadingDraft = false
            }
        }
    }
    
    /// Saves: end current set, create new IntentionSet with new/updated intentions
    private func saveAndDismiss() {
        // Filter to non-empty titles
        let valid = draftIntentions
            .map { d in
                var c = d
                c.title = c.title.trimmingCharacters(in: .whitespaces)
                return c
            }
            .filter { !$0.title.isEmpty }
        
        guard !valid.isEmpty else {
            dismiss()
            return
        }
        
        do {
            // 1. Save each intention (create or update) and collect IDs
            var intentionIds: [String] = []
            for draft in valid {
                let intention = draft.toIntention()
                try IntentionStore.shared.saveIntention(intention)
                intentionIds.append(intention.id)
            }
            
            // 2. Update current IntentionSet in place (same ID) so progress entries stay linked
            _ = try IntentionSetStore.shared.updateCurrentIntentionSet(intentionIds: intentionIds)
            
            AppLogger.log(AppLogger.STORE, "EditIntentions saved IntentionSet with \(intentionIds.count) intentions")
            
            dismiss()
        } catch {
            AppLogger.log(AppLogger.ERR, "EditIntentions save failed error=\"\(error.localizedDescription)\"")
        }
    }
}

/// Single editable intention row
private struct IntentionEditRow: View {
    @Binding var draft: DraftIntention
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $draft.title)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                TextField("Target", value: $draft.targetValue, format: .number)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                
                Picker("Unit", selection: $draft.unit) {
                    ForEach(DraftIntention.unitOptions, id: \.self) { unit in
                        Text(unit).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 100)
            }
            
            Picker("Timeframe", selection: $draft.timeframe) {
                Text("Daily").tag("daily")
                Text("Weekly").tag("weekly")
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    EditIntentionsView()
}
