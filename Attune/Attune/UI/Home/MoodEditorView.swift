//
//  MoodEditorView.swift
//  Attune
//
//  Simple mood editor: quick pick list + intensity (0-10). Slice A: migrated to 0-10 scale.
//  Saves as manual override (isManualOverride=true). Clear allows GPT to overwrite.
//

import SwiftUI

/// Preset mood labels for quick selection
private let moodLabels = ["Calm", "Focused", "Happy", "Neutral", "Anxious", "Stressed", "Tired"]

struct MoodEditorView: View {
    @Environment(\.dismiss) private var dismiss
    
    let dateKey: String
    let onSaved: () -> Void
    
    /// Mood score 0-10 (0 = lowest, 10 = highest). Slice A: migrated from -2..+2.
    @State private var selectedLabel: String?
    @State private var moodScore: Int = 5
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Mood") {
                    ForEach(moodLabels, id: \.self) { label in
                        Button(action: { selectedLabel = label }) {
                            HStack {
                                Text(label)
                                Spacer()
                                if selectedLabel == label {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
                
                Section("Intensity") {
                    HStack {
                        Text("Score (0-10)")
                        Spacer()
                        Picker("", selection: $moodScore) {
                            ForEach(0...10, id: \.self) { n in
                                Text("\(n)").tag(n)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 80, height: 100)
                    }
                }
                
                Section {
                    Button(role: .destructive, action: clearMood) {
                        Label("Clear (allow GPT to set)", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Mood")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAndDismiss()
                    }
                }
            }
            .onAppear {
                loadExistingMood()
            }
        }
    }
    
    private func loadExistingMood() {
        guard let mood = DailyMoodStore.shared.loadDailyMood(dateKey: dateKey) else { return }
        selectedLabel = mood.moodLabel
        moodScore = mood.moodScore ?? 5
    }
    
    private func saveAndDismiss() {
        do {
            try DailyMoodStore.shared.setMoodManual(
                dateKey: dateKey,
                moodLabel: selectedLabel,
                moodScore: moodScore
            )
            onSaved()
            dismiss()
        } catch {
            AppLogger.log(AppLogger.ERR, "MoodEditor save failed error=\"\(error.localizedDescription)\"")
        }
    }
    
    private func clearMood() {
        do {
            try DailyMoodStore.shared.clearManualOverride(dateKey: dateKey)
            onSaved()
            dismiss()
        } catch {
            AppLogger.log(AppLogger.ERR, "MoodEditor clear failed error=\"\(error.localizedDescription)\"")
        }
    }
}

#Preview {
    MoodEditorView(dateKey: AppPaths.dateKey(from: Date()), onSaved: {})
}
