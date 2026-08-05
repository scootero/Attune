//
//  MoodEditorView.swift
//  Attune
//
//  Clear 0-10 mood score with optional descriptive tags.
//  Saves as manual override. Clearing allows Attune to update mood from a check-in.
//

import SwiftUI

/// Preset mood labels for quick selection
private let moodLabels = ["Calm", "Focused", "Happy", "Energized", "Neutral", "Tired", "Anxious", "Stressed"]

struct MoodEditorView: View {
    @Environment(\.dismiss) private var dismiss
    
    let dateKey: String
    let onSaved: () -> Void
    
    /// Mood score 0-10 (0 = lowest, 10 = highest). Slice A: migrated from -2..+2.
    @State private var selectedLabel: String?
    @State private var moodScore: Int = 5
    @State private var hasExistingMood = false

    private let tagColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                AttuneScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(spacing: 10) {
                            Text("\(moodScore)")
                                .font(.system(size: 64, weight: .bold, design: .rounded))
                                .foregroundStyle(AttuneTheme.textPrimary)
                                .contentTransition(.numericText())
                            Text("out of 10 · \(scoreDescription)")
                                .font(.headline)
                                .foregroundStyle(AttuneTheme.accent)

                            Slider(
                                value: Binding(
                                    get: { Double(moodScore) },
                                    set: { moodScore = Int($0.rounded()) }
                                ),
                                in: 0...10,
                                step: 1
                            )
                            .tint(AttuneTheme.accent)
                            .accessibilityLabel("Mood score")
                            .accessibilityValue("\(moodScore) out of 10")

                            HStack {
                                Text("Very low")
                                Spacer()
                                Text("Excellent")
                            }
                            .font(.caption)
                            .foregroundStyle(AttuneTheme.textTertiary)
                        }
                        .padding(20)
                        .attuneCard()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Add a feeling")
                                .font(.headline)
                                .foregroundStyle(AttuneTheme.textPrimary)
                            Text("Optional · choose one that fits best")
                                .font(.subheadline)
                                .foregroundStyle(AttuneTheme.textSecondary)

                            LazyVGrid(columns: tagColumns, spacing: 10) {
                                ForEach(moodLabels, id: \.self) { label in
                                    Button {
                                        selectedLabel = selectedLabel == label ? nil : label
                                    } label: {
                                        HStack {
                                            Text(label)
                                            Spacer()
                                            if selectedLabel == label {
                                                Image(systemName: "checkmark.circle.fill")
                                            }
                                        }
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(selectedLabel == label ? Color.black.opacity(0.78) : AttuneTheme.textPrimary)
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: 44)
                                        .background(
                                            selectedLabel == label ? AttuneTheme.accent : AttuneTheme.surfaceStrong,
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(selectedLabel == label ? Color.clear : AttuneTheme.border)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(18)
                        .attuneCard()

                        Button(action: saveAndDismiss) {
                            Text("Save Mood")
                        }
                        .buttonStyle(AttunePrimaryButtonStyle())

                        if hasExistingMood {
                            Button(role: .destructive, action: clearMood) {
                                Label("Clear mood and let Attune update it", systemImage: "trash")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(AttuneTheme.recording)
                        }
                    }
                    .padding(.horizontal, AttuneTheme.horizontalPadding)
                    .padding(.top, 14)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle("Today's Mood")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                loadExistingMood()
            }
        }
    }
    
    private func loadExistingMood() {
        guard let mood = DailyMoodStore.shared.loadDailyMood(dateKey: dateKey) else { return }
        hasExistingMood = mood.moodLabel != nil || mood.moodScore != nil
        selectedLabel = mood.moodLabel
        moodScore = mood.moodScore ?? 5
    }

    private var scoreDescription: String {
        switch moodScore {
        case 0...2: return "Having a hard day"
        case 3...4: return "A little low"
        case 5: return "In the middle"
        case 6...7: return "Doing well"
        case 8...9: return "Feeling strong"
        default: return "Excellent"
        }
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
