//
//  AddEditIntentionView.swift
//  Attune
//
//  Redesigned single-intention add/edit page with glass card styling,
//  unit-aware slider ranges, and two-way sync between slider + manual input.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Mode for the unified add/edit intention page.
enum AddEditIntentionMode {
    /// Creating a brand-new intention draft.
    case create
    /// Editing an existing intention draft.
    case edit
}

/// Unit-aware slider configuration.
private struct IntentionValueConfig {
    /// Inclusive minimum value for the slider.
    let minValue: Double
    /// Inclusive maximum value for the slider.
    let maxValue: Double
    /// Step value used by both slider and manual snapping.
    let stepSize: Double
    /// Default value applied when the unit changes.
    let defaultValue: Double
}

/// Unified add/edit screen that matches the redesigned interaction model.
struct AddEditIntentionView: View {
    /// Indicates whether this page is creating or editing.
    let mode: AddEditIntentionMode
    /// Initial draft payload passed in by parent.
    let draft: DraftIntention
    /// Called when the user cancels without saving local changes.
    let onCancel: () -> Void
    /// Called when the user saves a valid draft.
    let onSave: (DraftIntention) -> Void
    
    /// Editable title text.
    @State private var titleText: String
    /// Editable numeric value bound to slider and manual field.
    @State private var targetValue: Double
    /// Unit key selected from the pill row.
    @State private var selectedUnit: String
    /// Custom unit text shown when selected unit is "custom".
    @State private var customUnitText: String
    /// Timeframe value retained from existing flow.
    @State private var timeframe: String
    /// Manual numeric text input synced with the slider value.
    @State private var manualValueText: String
    /// Guard that prevents manual text-change loops during programmatic sync.
    @State private var isSyncingManualTextFromValue = false
    /// Stores last snapped value for lightweight threshold haptic feedback.
    @State private var lastHapticValue: Double?
    /// Focus state for the title field.
    @FocusState private var isTitleFocused: Bool
    /// Focus state for custom unit field.
    @FocusState private var isCustomUnitFocused: Bool
    /// Focus state for manual value field.
    @FocusState private var isManualValueFocused: Bool
    
    /// All selectable units shown in the horizontal pill row.
    private let unitPills: [String] = ["minutes", "pages", "steps", "sessions", "reps", "cups", "glasses", "times", "custom"]
    
    /// Creates the unified add/edit page from an existing draft payload.
    init(mode: AddEditIntentionMode, draft: DraftIntention, onCancel: @escaping () -> Void, onSave: @escaping (DraftIntention) -> Void) {
        self.mode = mode
        self.draft = draft
        self.onCancel = onCancel
        self.onSave = onSave
        
        let normalizedUnit = Self.normalizedUnitSelection(for: draft.unit)
        let customUnit = normalizedUnit == "custom" ? draft.unit : ""
        let initialConfig = Self.valueConfig(forUnit: normalizedUnit == "custom" ? customUnit : normalizedUnit)
        let clampedValue = Self.snappedAndClampedValue(draft.targetValue, config: initialConfig)
        
        _titleText = State(initialValue: draft.title)
        _targetValue = State(initialValue: clampedValue)
        _selectedUnit = State(initialValue: normalizedUnit)
        _customUnitText = State(initialValue: customUnit)
        _timeframe = State(initialValue: draft.timeframe)
        _manualValueText = State(initialValue: Self.displayString(for: clampedValue))
    }
    
    var body: some View {
        ZStack {
            // Deep navy-to-emerald inspired background gradient with subtle layered fog.
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.04, green: 0.08, blue: 0.17),
                    Color(red: 0.05, green: 0.16, blue: 0.20),
                    Color(red: 0.03, green: 0.10, blue: 0.15)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Radial ambient glow behind the main card to reinforce depth.
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.15, green: 0.53, blue: 0.63).opacity(0.35),
                    Color.clear
                ]),
                center: .top,
                startRadius: 40,
                endRadius: 460
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Main frosted card container for all controls.
                    VStack(alignment: .leading, spacing: 20) {
                        titleSection
                        unitSection
                        valueSection
                        timeframeSection
                    }
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(mode == .create ? "New Intention" : "Edit Intention")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onCancel()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(mode == .create ? "Save" : "Update") {
                    handleSave()
                }
                .disabled(!isValidDraft)
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomSaveButton
        }
        .onChange(of: targetValue) { _, newValue in
            syncManualText(from: newValue)
            maybeTriggerHaptic(for: newValue)
        }
        .onChange(of: manualValueText) { _, newValue in
            guard !isSyncingManualTextFromValue else { return }
            applyManualValueInput(newValue)
        }
        .onChange(of: selectedUnit) { _, _ in
            if selectedUnit != "custom" {
                isCustomUnitFocused = false
            }
            applyUnitChangeReset()
        }
        .onChange(of: customUnitText) { _, _ in
            guard selectedUnit == "custom" else { return }
            applyUnitChangeReset()
        }
    }
    
    /// Large title field with subtle active-state affordance.
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("What do you want to track?", text: $titleText)
                .font(.system(size: 20, weight: .medium))
                .focused($isTitleFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isTitleFocused ? Color(red: 0.17, green: 0.75, blue: 0.84) : Color.white.opacity(0.12), lineWidth: isTitleFocused ? 1.6 : 1)
                )
                .scaleEffect(isTitleFocused ? 1.01 : 1.0)
                .animation(.easeInOut(duration: 0.18), value: isTitleFocused)
        }
    }
    
    /// Unit label plus horizontally scrollable pill buttons.
    private var unitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unit")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(unitPills, id: \.self) { unit in
                        Button(action: { selectedUnit = unit }) {
                            Text(Self.displayLabel(for: unit))
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(selectedUnit == unit ? .black : .white.opacity(0.9))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(
                                            selectedUnit == unit
                                            ? LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color(red: 0.17, green: 0.70, blue: 0.96),
                                                    Color(red: 0.14, green: 0.77, blue: 0.74)
                                                ]),
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                            : LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color.white.opacity(0.10),
                                                    Color.white.opacity(0.06)
                                                ]),
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(selectedUnit == unit ? 0.0 : 0.16), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            
            if selectedUnit == "custom" {
                TextField("Custom unit name", text: $customUnitText)
                    .textInputAutocapitalization(.words)
                    .focused($isCustomUnitFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isCustomUnitFocused ? Color(red: 0.78, green: 0.48, blue: 0.24) : Color.white.opacity(0.12), lineWidth: 1)
                    )
            }
        }
    }
    
    /// Slider + live value + manual entry with two-way sync.
    private var valueSection: some View {
        let config = currentValueConfig
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Slider(value: $targetValue, in: config.minValue...config.maxValue, step: config.stepSize)
                    .tint(Color(red: 0.17, green: 0.75, blue: 0.84))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Target value")
                    .accessibilityValue("\(Int(targetValue)) \(resolvedUnitName)")
                
                Text("\(Self.displayString(for: targetValue)) \(displayUnitAbbreviation)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
            }
            
            VStack(spacing: 6) {
                TextField("Enter value", text: $manualValueText)
                    .keyboardType(.decimalPad)
                    .focused($isManualValueFocused)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
                
                Text("Range: \(Int(config.minValue))–\(Int(config.maxValue)) • Step: \(Self.displayString(for: config.stepSize))")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.72))
            }
        }
    }
    
    /// Existing timeframe setting preserved to avoid behavior regressions.
    private var timeframeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Timeframe")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))
            
            Picker("Timeframe", selection: $timeframe) {
                Text("Daily").tag("daily")
                Text("Weekly").tag("weekly")
            }
            .pickerStyle(.segmented)
        }
    }
    
    /// Sticky bottom button for create/update action.
    private var bottomSaveButton: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.clear,
                            Color.black.opacity(0.12)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 8)
            
            Button(action: {
                isTitleFocused = false
                isCustomUnitFocused = false
                isManualValueFocused = false
                handleSave()
            }) {
                Text(mode == .create ? "Create Intention" : "Update Intention")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                isValidDraft
                                ? LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.17, green: 0.70, blue: 0.96),
                                        Color(red: 0.14, green: 0.77, blue: 0.74)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                : LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.16),
                                        Color.white.opacity(0.10)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .disabled(!isValidDraft)
            .buttonStyle(.plain)
            .background(Color.black.opacity(0.18))
        }
        .background(.ultraThinMaterial)
    }
    
    /// True when title and unit meet minimum validity checks.
    private var isValidDraft: Bool {
        !trimmedTitle.isEmpty && !resolvedUnitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Title normalized for validation and save output.
    private var trimmedTitle: String {
        titleText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Effective unit string used in display and save output.
    private var resolvedUnitName: String {
        if selectedUnit == "custom" {
            let trimmedCustom = customUnitText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedCustom.isEmpty ? "units" : trimmedCustom
        }
        return selectedUnit
    }
    
    /// Unit abbreviation shown in the live value label.
    private var displayUnitAbbreviation: String {
        switch resolvedUnitName.lowercased() {
        case "minutes":
            return "min"
        case "pages":
            return "pg"
        default:
            return resolvedUnitName
        }
    }
    
    /// Current slider configuration derived from the selected/effective unit.
    private var currentValueConfig: IntentionValueConfig {
        Self.valueConfig(forUnit: resolvedUnitName)
    }
    
    /// Applies snapped/clamped target reset when unit changes.
    private func applyUnitChangeReset() {
        let config = currentValueConfig
        targetValue = Self.snappedAndClampedValue(config.defaultValue, config: config)
        syncManualText(from: targetValue)
    }
    
    /// Syncs manual text from numeric value using loop guard.
    private func syncManualText(from value: Double) {
        isSyncingManualTextFromValue = true
        manualValueText = Self.displayString(for: value)
        isSyncingManualTextFromValue = false
    }
    
    /// Parses manual text and updates target value using clamp + step snapping.
    private func applyManualValueInput(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return
        }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(normalized) else {
            return
        }
        let adjusted = Self.snappedAndClampedValue(parsed, config: currentValueConfig)
        if adjusted != targetValue {
            targetValue = adjusted
        } else {
            syncManualText(from: adjusted)
        }
    }
    
    /// Saves by returning a normalized DraftIntention to parent.
    private func handleSave() {
        guard isValidDraft else { return }
        let savedDraft = DraftIntention(
            id: draft.id,
            title: trimmedTitle,
            targetValue: Self.snappedAndClampedValue(targetValue, config: currentValueConfig),
            unit: resolvedUnitName,
            timeframe: timeframe.lowercased() == "weekly" ? "weekly" : "daily"
        )
        onSave(savedDraft)
    }
    
    /// Optional light haptic every significant snapped step.
    private func maybeTriggerHaptic(for value: Double) {
        let snapped = Self.snappedAndClampedValue(value, config: currentValueConfig)
        if let last = lastHapticValue, last == snapped {
            return
        }
        lastHapticValue = snapped
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }
    
    /// Maps existing units to a selectable pill key.
    private static func normalizedUnitSelection(for unit: String) -> String {
        let lowered = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowered.isEmpty {
            return "minutes"
        }
        if ["minutes", "pages", "steps", "sessions", "reps", "cups", "glasses", "times", "custom"].contains(lowered) {
            return lowered
        }
        return "custom"
    }
    
    /// Human-readable label for unit pills.
    private static func displayLabel(for unit: String) -> String {
        let lowered = unit.lowercased()
        if lowered.isEmpty { return "Unit" }
        return lowered.prefix(1).uppercased() + lowered.dropFirst()
    }
    
    /// Returns a unit-specific value config with safe defaults.
    private static func valueConfig(forUnit unit: String) -> IntentionValueConfig {
        switch unit.lowercased() {
        case "minutes":
            return IntentionValueConfig(minValue: 0, maxValue: 240, stepSize: 5, defaultValue: 30)
        case "pages":
            return IntentionValueConfig(minValue: 0, maxValue: 200, stepSize: 1, defaultValue: 10)
        case "steps":
            return IntentionValueConfig(minValue: 0, maxValue: 20_000, stepSize: 500, defaultValue: 5_000)
        default:
            return IntentionValueConfig(minValue: 0, maxValue: 100, stepSize: 1, defaultValue: 10)
        }
    }
    
    /// Clamps a value to config range and snaps it to nearest step.
    private static func snappedAndClampedValue(_ value: Double, config: IntentionValueConfig) -> Double {
        let clamped = min(config.maxValue, max(config.minValue, value))
        let stepped = (clamped / config.stepSize).rounded() * config.stepSize
        return min(config.maxValue, max(config.minValue, stepped))
    }
    
    /// Formats values without trailing decimals for whole numbers.
    private static func displayString(for value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}
