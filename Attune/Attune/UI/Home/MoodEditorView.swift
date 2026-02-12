//
//  MoodEditorView.swift
//  Attune
//
//  Simple mood editor: quick pick list + optional intensity (-2..+2).
//  Saves as manual override (isManualOverride=true). Clear allows GPT to overwrite. Slice 5.
//

import SwiftUI

/// Preset mood labels for quick selection
private let moodLabels = ["Calm", "Focused", "Happy", "Neutral", "Anxious", "Stressed", "Tired"]

struct MoodEditorView: View {
    @Environment(\.dismiss) private var dismiss
    
    let dateKey: String
    let onSaved: () -> Void
    
    @State private var selectedLabel: String?
    @State private var moodScore: Int = 0  // -2 to +2
    
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
                        Text("Score")
                        Spacer()
                        Picker("", selection: $moodScore) {
                            ForEach(-2...2, id: \.self) { n in
                                Text(intensityLabel(n)).tag(n)
                            }
                        }
                        .pickerStyle(.segmented)
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
    
    private func intensityLabel(_ n: Int) -> String {
        switch n {
        case -2: return "−2"
        case -1: return "−1"
        case 0: return "0"
        case 1: return "+1"
        case 2: return "+2"
        default: return "\(n)"
        }
    }
    
    private func loadExistingMood() {
        guard let mood = DailyMoodStore.shared.loadDailyMood(dateKey: dateKey) else { return }
        selectedLabel = mood.moodLabel
        moodScore = mood.moodScore ?? 0
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
