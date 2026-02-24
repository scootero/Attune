//
//  EditIntentionsView.swift
//  Attune
//
//  Draft editing of intentions (max 10). On Save: ends current IntentionSet,
//  creates new one with updated Intention records. Slice 5.
//

import SwiftUI
import UIKit // needed for haptic feedback generator used in slider snapping

/// Editable draft of an intention (mutable for form binding)
struct DraftIntention: Identifiable {
    var id: String
    var title: String
    var targetValue: Double
    var unit: String
    var timeframe: String  // "daily" or "weekly"
    
    static let maxCount = 10  // maximum intentions user can add; single source of truth for cap
    
    static let unitOptions = ["pages", "minutes", "sessions", "steps", "reps", "cups", "glasses", "times"] // added "times" to align with parser defaults
    
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
    
    /// Draft intentions (max 10, from DraftIntention.maxCount)
    @State private var draftIntentions: [DraftIntention] = [] // holds current working list for existing intentions
    /// True while loading draft from disk on background (avoids blocking main thread)
    @State private var isLoadingDraft = true // gates UI until initial load completes
    /// Stores the draft id selected from swipe-to-delete so alert can confirm intent.
    @State private var pendingDeleteDraftId: String? // tracks which row user wants to delete
    /// Stores a friendly title for the delete confirmation alert message.
    @State private var pendingDeleteDraftTitle: String = "" // makes delete prompt human-friendly
    /// Inline Add card working draft (separate from existing list).
    @State private var addDraft: DraftIntention = DraftIntention.empty() // captures new intention fields before commit
    /// Whether the Add card is expanded.
    @State private var isAddExpanded: Bool = false // ensures only one card expanded at a time per spec
    /// Currently expanded existing intention id, if any.
    @State private var expandedEditId: String? // mutually exclusive with add card expansion
    /// Baseline snapshot of drafts for dirty-state detection.
    @State private var baselineDrafts: [DraftIntention] = [] // original loaded drafts for change comparison
    /// Baseline snapshot of add draft for dirty-state detection.
    @State private var baselineAddDraft: DraftIntention = DraftIntention.empty() // original add-card state (empty)
    /// Shared haptic generator for slider snaps.
    private let hapticEngine = UIImpactFeedbackGenerator(style: .light) // reused to avoid reallocating per snap
    
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
                        AddIntentionCard( // inline Add card per spec
                            draft: $addDraft, // bind to add draft state
                            isExpanded: $isAddExpanded, // controls expansion
                            disableAdd: draftIntentions.count >= DraftIntention.maxCount, // enforce max cap
                            onExpand: { collapseAllForAdd() }, // ensure only one expanded at a time
                            onParsed: { parsed in applyParsedToAddDraft(parsed) }, // route record parse into add draft
                            hapticEngine: hapticEngine, // share haptic generator
                            onDirty: { triggerDirtyCheck() } // recompute dirty when add card changes
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)) // keep card breathing room
                        .listRowSeparator(.hidden) // hide separators for glass cards
                        .listRowBackground(Color.clear) // let glass card show
                        
                        ForEach($draftIntentions) { $draft in // iterate with binding so inline edits write through
                            VStack(spacing: 8) { // stack summary + optional editor
                                Button(action: { toggleEditExpansion(for: draft.id) }) { // tap to expand/collapse edit card
                                    IntentionSummaryRow( // summary row retained for quick scan
                                        draft: draft, // pass current draft
                                        variation: IntentionCardVariation.forId(draft.id) // deterministic palette
                                    )
                                }
                                .buttonStyle(.plain) // keep custom styling
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) { // deletion affordance
                                    Button(role: .destructive) {
                                        pendingDeleteDraftId = draft.id // track row for alert
                                        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines) // normalize title
                                        pendingDeleteDraftTitle = trimmedTitle.isEmpty ? "this intention" : "\"\(trimmedTitle)\"" // friendly prompt
                                    } label: {
                                        Label("Delete", systemImage: "trash") // icon for delete
                                    }
                                }
                                
                                if expandedEditId == draft.id { // show editor only for active row
                                    InlineIntentionEditor( // inline editor with slider + fields
                                        draft: $draft, // bind to this row
                                        variation: IntentionCardVariation.forId(draft.id), // palette reuse
                                        onValueChanged: { triggerDirtyCheck() }, // recompute dirty when edits occur
                                        onUnitChanged: { triggerDirtyCheck() }, // recompute dirty on unit changes
                                        hapticEngine: hapticEngine // shared generator
                                    )
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)) // spacing for glass cards
                            .listRowSeparator(.hidden) // hide separators under glass
                            .listRowBackground(Color.clear) // transparent background for gradient
                        }
                    }
                    .scrollContentBackground(.hidden) // allow custom background
                    .listStyle(.plain) // plain list keeps spacing predictable and lighter to render while typing
                    .scrollDismissesKeyboard(.interactively) // let drag gestures dismiss keyboard smoothly // reduces abrupt keyboard/layout interactions
                    .background(
                        CyberBackground() // reuse cyber-glass gradient to match Home aesthetic
                            .ignoresSafeArea() // extend behind list
                    )
                }
            }
            .navigationTitle("Edit Intentions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancelChanges() // restore baseline then dismiss
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
            .alert("Delete intention?", isPresented: Binding(
                get: { pendingDeleteDraftId != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteDraftId = nil
                        pendingDeleteDraftTitle = ""
                    }
                }
            )) {
                Button("No", role: .cancel) {
                    pendingDeleteDraftId = nil
                    pendingDeleteDraftTitle = ""
                }
                Button("Yes", role: .destructive) {
                    deletePendingDraft()
                }
            } message: {
                Text("Delete \(pendingDeleteDraftTitle)?")
            }
        }
    }
    
    private var canSave: Bool {
        hasChanges // requires real changes
        && !validIntentionsForSave.isEmpty // requires at least one valid intention
    } // end canSave
    
    /// Returns intentions to persist (existing + add card when valid).
    private var validIntentionsForSave: [DraftIntention] {
        let trimmedExisting = draftIntentions.compactMap { draft -> DraftIntention? in // walk existing rows
            let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines) // normalize title
            guard !trimmedTitle.isEmpty else { return nil } // skip empty titles
            var cleaned = draft // copy to mutate safely
            cleaned.title = trimmedTitle // store trimmed title
            return cleaned // keep valid row
        }
        var results = trimmedExisting // start with existing
        let addTitle = addDraft.title.trimmingCharacters(in: .whitespacesAndNewlines) // check add draft title
        if !addTitle.isEmpty { // only include when non-empty
            var cleanedAdd = addDraft // copy for mutation
            cleanedAdd.title = addTitle // store trimmed title
            results.append(cleanedAdd) // append new intention
        }
        return results // final list
    } // end validIntentionsForSave
    
    /// Detects whether any changes exist compared to baseline snapshots.
    private var hasChanges: Bool {
        // Check add draft change
        if isDraftDifferent(addDraft, baselineAddDraft) { // compare add card to baseline
            return true // changed
        }
        // Check deletions or insertions
        if draftIntentions.count != baselineDrafts.count { // length mismatch signals change
            return true // changed
        }
        // Compare each baseline draft against current by id
        let currentById = Dictionary(uniqueKeysWithValues: draftIntentions.map { ($0.id, $0) }) // map current
        for base in baselineDrafts { // iterate baseline items
            guard let current = currentById[base.id] else { return true } // missing item means deletion
            if isDraftDifferent(current, base) { // field difference
                return true // changed
            }
        }
        return false // no differences detected
    } // end hasChanges
    
    /// Field-wise comparison for dirty tracking.
    private func isDraftDifferent(_ lhs: DraftIntention, _ rhs: DraftIntention) -> Bool {
        lhs.id != rhs.id // id difference counts as change
        || lhs.title != rhs.title // title change
        || lhs.targetValue != rhs.targetValue // target change
        || lhs.unit != rhs.unit // unit change
        || lhs.timeframe.lowercased() != rhs.timeframe.lowercased() // timeframe change with normalization
    } // end isDraftDifferent
    
    private func deleteDraft(at offsets: IndexSet) {
        draftIntentions.remove(atOffsets: offsets)
    }
    
    /// Deletes the draft selected by swipe action after user confirms the alert.
    private func deletePendingDraft() {
        guard let pendingDeleteDraftId else { return }
        draftIntentions.removeAll { $0.id == pendingDeleteDraftId }
        self.pendingDeleteDraftId = nil
        self.pendingDeleteDraftTitle = ""
        triggerDirtyCheck() // mark dirty after deletion
    }
    
    /// Ensures only the Add card is expanded.
    private func collapseAllForAdd() {
        expandedEditId = nil // collapse any open edit row
        isAddExpanded = true // expand add card
    } // end collapseAllForAdd
    
    /// Toggles expansion for a specific intention id while collapsing others.
    private func toggleEditExpansion(for id: String) {
        if expandedEditId == id { // if already open
            expandedEditId = nil // collapse
        } else {
            isAddExpanded = false // collapse add card
            expandedEditId = id // expand target row
        }
    } // end toggleEditExpansion
    
    /// Applies parsed intentions into the Add card fields (first parsed only).
    private func applyParsedToAddDraft(_ parsed: [ParsedIntention]) {
        guard let first = parsed.first else { return } // nothing to apply
        isAddExpanded = true // open add card to show populated fields
        expandedEditId = nil // ensure exclusivity
        addDraft.title = first.title.trimmingCharacters(in: .whitespacesAndNewlines) // set parsed title
        addDraft.unit = (first.unit?.isEmpty == false ? first.unit! : "times") // default to times
        addDraft.targetValue = max(0, first.target ?? 1) // default to 1 if missing
        triggerDirtyCheck() // recompute dirty state after population
    } // end applyParsedToAddDraft
    
    /// Forces a refresh of dirty-state dependent UI.
    private func triggerDirtyCheck() {
        // No-op body; accessing hasChanges recomputes via state reads.
        _ = hasChanges // touch computed property to mark dependency
    } // end triggerDirtyCheck
    
    /// Restores drafts to baseline and dismisses without saving.
    private func cancelChanges() {
        draftIntentions = baselineDrafts // revert existing drafts
        addDraft = baselineAddDraft // revert add card
        expandedEditId = nil // collapse editors
        isAddExpanded = false // collapse add card
        dismiss() // close sheet
    } // end cancelChanges
    
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
                baselineDrafts = draftIntentions // capture baseline for dirty tracking
                addDraft = DraftIntention.empty() // reset add card to empty on load
                baselineAddDraft = addDraft // align baseline add draft id with current add draft
                expandedEditId = nil // collapse edits on load
                isAddExpanded = false // collapse add card on load
                isLoadingDraft = false
            }
        }
    }
    
    /// Saves: end current set, create new IntentionSet with new/updated intentions
    private func saveAndDismiss() {
        let valid = validIntentionsForSave // gather cleaned intentions
        guard !valid.isEmpty else { // ensure at least one intention
            dismiss() // nothing to save, dismiss
            return // stop
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
            
            baselineDrafts = draftIntentions // update baseline to latest saved existing drafts
            addDraft = DraftIntention.empty() // clear add card after save
            baselineAddDraft = addDraft // align baseline add draft with cleared add draft
            isAddExpanded = false // collapse add card post-save
            expandedEditId = nil // collapse edits post-save
            
            dismiss()
        } catch {
            AppLogger.log(AppLogger.ERR, "EditIntentions save failed error=\"\(error.localizedDescription)\"")
        }
    }
}

/// Compact summary row that previews intention title, value, unit, and timeframe.
private struct IntentionSummaryRow: View {
    /// Draft model used to render the row summary.
    let draft: DraftIntention
    /// Stable color variation used for gentle card tinting.
    let variation: IntentionCardVariation
    
    var body: some View {
        HStack(spacing: 12) { // horizontal layout keeps details scannable in a dense list
            VStack(alignment: .leading, spacing: 6) { // text stack groups title and metadata
                Text(displayTitle) // primary intention title text with empty fallback
                    .font(.headline) // clear hierarchy for quick scanning
                    .foregroundColor(.primary) // system-adaptive text color
                Text("\(displayValue) \(displayUnit) • \(displayTimeframe)") // concise metadata line with value + unit + cadence
                    .font(.subheadline) // secondary text scale for supporting details
                    .foregroundColor(.secondary) // reduced emphasis while remaining readable
            }
            Spacer() // push chevron to trailing edge for affordance clarity
            Image(systemName: "chevron.right") // communicates that tapping opens editor details
                .font(.footnote.weight(.semibold)) // subtle but visible chevron sizing
                .foregroundColor(.secondary) // low-emphasis icon tone
        }
        .padding(12) // internal spacing for comfortable tap target and visual breathing room
        .background(IntentionCardBackground(variation: variation)) // reuse existing soft card background style
        .contentShape(RoundedRectangle(cornerRadius: 16)) // preserve full rounded hit area for reliable taps
    }
    
    /// Title fallback for drafts with empty text.
    private var displayTitle: String {
        let trimmed = draft.title.trimmingCharacters(in: .whitespacesAndNewlines) // trim whitespace to decide if title is visually empty
        return trimmed.isEmpty ? "Untitled Intention" : trimmed // show friendly placeholder when no title exists yet
    }
    
    /// Value display that avoids trailing decimals for whole numbers.
    private var displayValue: String {
        if draft.targetValue.rounded() == draft.targetValue { // detect whole numbers so we can avoid ".0"
            return String(Int(draft.targetValue)) // compact integer display for cleaner summaries
        }
        return String(draft.targetValue) // preserve decimal detail when needed
    }
    
    /// Unit fallback for safety if unit is somehow blank.
    private var displayUnit: String {
        let trimmed = draft.unit.trimmingCharacters(in: .whitespacesAndNewlines) // normalize whitespace before display
        return trimmed.isEmpty ? "units" : trimmed // fallback keeps summary readable even with malformed data
    }
    
    /// Human-friendly timeframe display string.
    private var displayTimeframe: String {
        draft.timeframe.lowercased() == "weekly" ? "weekly" : "daily" // normalize unexpected values to daily for consistent copy
    }
}

/// Unit-aware slider configuration for inline editors.
private struct IntentionValueConfig {
    let minValue: Double // inclusive minimum
    let maxValue: Double // inclusive maximum
    let stepSize: Double // slider step
    let defaultValue: Double // default when unit changes
}

/// Inline editor used for both Add card and expanded edit rows.
private struct InlineIntentionEditor: View {
    @Binding var draft: DraftIntention // binding to mutate draft in parent
    let variation: IntentionCardVariation // color palette
    let onValueChanged: () -> Void // notifies parent to recompute dirty state
    let onUnitChanged: () -> Void // notifies parent to recompute dirty state on unit changes
    let hapticEngine: UIImpactFeedbackGenerator // shared haptic generator
    
    @State private var manualValueText: String // text backing for manual entry
    @State private var isSyncingManualText: Bool = false // guards feedback loops
    private let snapThreshold: Double = 2 // within 2 units of multiple-of-10 triggers snap
    
    init(draft: Binding<DraftIntention>, variation: IntentionCardVariation, onValueChanged: @escaping () -> Void, onUnitChanged: @escaping () -> Void, hapticEngine: UIImpactFeedbackGenerator) {
        self._draft = draft // store binding
        self.variation = variation // store palette
        self.onValueChanged = onValueChanged // store callback
        self.onUnitChanged = onUnitChanged // store callback
        self.hapticEngine = hapticEngine // store haptic generator
        _manualValueText = State(initialValue: Self.displayString(for: draft.wrappedValue.targetValue)) // seed text from value
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { // stack fields with tight spacing
            HStack {
                TextField("Title", text: $draft.title) // title input
                    .textFieldStyle(.plain) // plain style for glass aesthetic
                    .foregroundColor(.white) // white text for dark bg
                    .padding(.horizontal, 12) // inset
                    .padding(.vertical, 10) // vertical pad
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.08)) // subtle glass fill
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1) // thin stroke
                    )
                    .onChange(of: draft.title) { _, _ in // title change hook
                        onValueChanged() // mark dirty
                    }
            }
            
            VStack(alignment: .leading, spacing: 10) { // value + slider
                HStack(spacing: 12) {
                    Slider(
                        value: $draft.targetValue, // bind to numeric value
                        in: valueConfig.minValue...valueConfig.maxValue, // range by unit
                        step: valueConfig.stepSize, // step size
                        onEditingChanged: { isEditing in // snap only on release
                            if !isEditing { // release moment
                                applySoftSnap() // snap to nearby multiple of 10
                            }
                        }
                    )
                    .tint(Color(red: 0.17, green: 0.75, blue: 0.84)) // teal slider tint for cyber look
                    .onChange(of: draft.targetValue) { _, newValue in // sync text as slider moves
                        syncManualText(from: newValue) // update manual field
                        onValueChanged() // propagate dirty state
                    }
                    
                    Text("\(Self.displayString(for: draft.targetValue)) \(displayUnitAbbreviation)") // live value label
                        .font(.system(size: 20, weight: .bold)) // bold for emphasis
                        .foregroundColor(.white) // white text
                        .monospacedDigit() // monospaced for stability
                        .onTapGesture { // allow manual focus via tap
                            // no-op; tap simply brings attention to manual field nearby
                        }
                }
                
                TextField("Enter value", text: $manualValueText) // manual numeric entry
                    .keyboardType(.decimalPad) // numeric keyboard
                    .multilineTextAlignment(.center) // center align
                    .padding(.horizontal, 12) // inset
                    .padding(.vertical, 10) // vertical pad
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.08)) // glass fill
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1) // thin stroke
                    )
                    .onChange(of: manualValueText) { _, newValue in // parse manual edits
                        applyManualValueInput(newValue) // sync numeric value
                    }
            }
            
            HStack(spacing: 12) {
                Picker("Unit", selection: $draft.unit) { // unit picker
                    ForEach(DraftIntention.unitOptions, id: \.self) { unit in
                        Text(unit).tag(unit) // unit option
                    }
                }
                .pickerStyle(.menu) // compact menu style
                .onChange(of: draft.unit) { _, _ in // unit changed
                    applyUnitReset() // reset value defaults for unit
                    onUnitChanged() // notify parent
                }
                
                Picker("Timeframe", selection: $draft.timeframe) { // timeframe picker
                    Text("Daily").tag("daily") // daily option
                    Text("Weekly").tag("weekly") // weekly option
                }
                .pickerStyle(.segmented) // segmented control
                .onChange(of: draft.timeframe) { _, _ in // timeframe change
                    onUnitChanged() // still counts as dirty
                }
            }
        }
        .padding(14) // card padding
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial) // glass material
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1) // subtle border
        )
    }
    
    /// Config derived from unit.
    private var valueConfig: IntentionValueConfig {
        switch draft.unit.lowercased() {
        case "minutes":
            return IntentionValueConfig(minValue: 0, maxValue: 240, stepSize: 5, defaultValue: 30) // minutes config
        case "pages":
            return IntentionValueConfig(minValue: 0, maxValue: 200, stepSize: 1, defaultValue: 10) // pages config
        case "steps":
            return IntentionValueConfig(minValue: 0, maxValue: 20_000, stepSize: 500, defaultValue: 5_000) // steps config
        default:
            return IntentionValueConfig(minValue: 0, maxValue: 100, stepSize: 1, defaultValue: 10) // default fallback
        }
    }
    
    /// Short unit abbreviation for label.
    private var displayUnitAbbreviation: String {
        switch draft.unit.lowercased() {
        case "minutes": return "min" // minutes abbreviation
        case "pages": return "pg" // pages abbreviation
        default: return draft.unit // fallback
        }
    }
    
    /// Applies soft snap near multiples of 10 after slider release.
    private func applySoftSnap() {
        let snapped = Self.softSnap(value: draft.targetValue, threshold: snapThreshold) // compute snapped value
        guard snapped != draft.targetValue else { return } // no snap needed
        draft.targetValue = snapped // apply snap
        syncManualText(from: snapped) // sync text
        hapticEngine.impactOccurred() // light haptic feedback
        onValueChanged() // notify parent
    }
    
    /// Syncs manual text field from numeric value.
    private func syncManualText(from value: Double) {
        isSyncingManualText = true // guard against recursion
        manualValueText = Self.displayString(for: value) // update text
        isSyncingManualText = false // release guard
    }
    
    /// Parses manual text and clamps/snap to config.
    private func applyManualValueInput(_ text: String) {
        guard !isSyncingManualText else { return } // skip loops
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines) // normalize
        if trimmed.isEmpty { return } // ignore empty
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".") // decimal separator support
        guard let parsed = Double(normalized) else { return } // ignore invalid
        let clamped = min(valueConfig.maxValue, max(valueConfig.minValue, parsed)) // clamp to range
        draft.targetValue = clamped // apply exact manual value (no snap to allow override)
        syncManualText(from: clamped) // reflect in text
        onValueChanged() // notify parent
    }
    
    /// Resets value when unit changes to its default, with snap + sync.
    private func applyUnitReset() {
        let defaultValue = valueConfig.defaultValue // derive default for unit
        draft.targetValue = defaultValue // apply default
        syncManualText(from: defaultValue) // sync text
        applySoftSnap() // ensure snap for consistency
    }
    
    /// Formats numeric display without trailing decimals when possible.
    private static func displayString(for value: Double) -> String {
        if value.rounded() == value { // whole number
            return String(Int(value)) // integer display
        }
        return String(format: "%.2f", value) // two-decimal display
    }
    
    /// Soft snaps toward nearest multiple of 10 when within threshold.
    private static func softSnap(value: Double, threshold: Double) -> Double {
        let nearest = (value / 10).rounded() * 10 // nearest multiple of 10
        if abs(nearest - value) <= threshold { // within soft zone
            return nearest // snap
        }
        return value // leave as-is
    }
}

/// Inline Add card that hosts Record + manual entry.
private struct AddIntentionCard: View {
    @Binding var draft: DraftIntention // add draft binding
    @Binding var isExpanded: Bool // expansion flag
    let disableAdd: Bool // disables interaction when at cap
    let onExpand: () -> Void // called when expanding add card
    let onParsed: ([ParsedIntention]) -> Void // routes parsed intentions into add draft
    let hapticEngine: UIImpactFeedbackGenerator // shared haptic
    let onDirty: () -> Void // dirty-state notifier
    
    @State private var recordStatus: String? = nil // local status message
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: {
                guard !disableAdd else { return } // prevent expansion when at cap
                onExpand() // collapse others, expand add
            }) {
                HStack {
                    Text("Add Intention") // header title
                        .font(.headline) // emphasize
                        .foregroundColor(.white) // white text
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down") // expand indicator
                        .foregroundColor(.white.opacity(0.8)) // softer icon
                }
                .padding(.vertical, 8) // padding for tap target
            }
            .buttonStyle(.plain) // keep custom styling
            .disabled(disableAdd) // respect cap
            
            if let recordStatus { // show status when present
                Text(recordStatus) // status text
                    .font(.footnote) // small font
                    .foregroundColor(.secondary) // subtle color
            }
            
            if isExpanded { // show body when expanded
                RecordIntentionsSection(onIntentionsParsed: { parsed in // embed record UI
                    onParsed(parsed) // populate add draft fields
                    recordStatus = parsed.isEmpty ? "No intentions found." : "Parsed into Add card. Review then Save." // status message
                    onDirty() // mark dirty
                })
                
                InlineIntentionEditor( // reuse editor for add card
                    draft: $draft, // bind to add draft
                    variation: IntentionCardVariation.forId(draft.id), // palette
                    onValueChanged: { onDirty() }, // dirty on value change
                    onUnitChanged: { onDirty() }, // dirty on unit change
                    hapticEngine: hapticEngine // shared haptic
                )
            }
        }
        .padding(14) // card padding
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial) // glass background
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1) // subtle stroke
        )
    }
}

/// Single editable intention row with premium card styling.
/// Uses subtle gradient, soft shadow, rounded corners, and pill-style inputs.
private struct IntentionEditRow: View {
    @Binding var draft: DraftIntention // bound editable draft model for this row // row edits write directly to parent state
    let variation: IntentionCardVariation // precomputed card palette for this row // avoids recomputing selection logic inside body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { // reduced spacing so each card is visually smaller
            // Title field: rounded background, soft look
            TextField("Title", text: $draft.title)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.tertiarySystemFill))
                )
            
            // Target value + unit row: pill-style value field, menu picker
            HStack(spacing: 12) {
                // Pill-shaped value input with tinted background
                TextField("Target", text: targetValueTextBinding)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(width: 72)
                    .background(
                        Capsule()
                            .fill(Color(.tertiarySystemFill))
                    )
                
                Picker("Unit", selection: $draft.unit) {
                    ForEach(DraftIntention.unitOptions, id: \.self) { unit in
                        Text(unit).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 100)
            }
            
            // Daily/Weekly segmented control; spacing replaces hard divider
            Picker("Timeframe", selection: $draft.timeframe) {
                Text("Daily").tag("daily")
                Text("Weekly").tag("weekly")
            }
            .pickerStyle(.segmented)
        }
        .padding(12) // reduced internal padding so cards are smaller and less heavy on screen
        .background(IntentionCardBackground(variation: variation)) // draw card directly around row content // lighter than listRowBackground compositing
        .contentShape(RoundedRectangle(cornerRadius: 16)) // keep full rounded row hit area consistent // improves gesture targeting for swipe interactions
    }
    
    /// String-based binding avoids expensive number formatter churn while user is typing.
    private var targetValueTextBinding: Binding<String> {
        Binding(
            get: {
                if draft.targetValue.rounded() == draft.targetValue {
                    return String(Int(draft.targetValue))
                }
                return String(draft.targetValue)
            },
            set: { newValue in
                let sanitized = newValue.replacingOccurrences(of: ",", with: ".")
                if sanitized.isEmpty {
                    draft.targetValue = 0
                    return
                }
                if let value = Double(sanitized) {
                    draft.targetValue = max(0, value)
                }
            }
        )
    }
}

/// Card background for intention rows: gradient + soft shadow. Used via listRowBackground.
private struct IntentionCardBackground: View {
    let variation: IntentionCardVariation
    
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        variation.topColor,
                        variation.bottomColor
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(variation.borderColor, lineWidth: 0.6) // subtle tinted border helps cards separate without heavy shadows
            )
    }
}

/// Defines soft, natural card color variations and deterministic selection by draft id.
private struct IntentionCardVariation {
    let topColor: Color
    let bottomColor: Color
    let borderColor: Color
    
    /// Soft, nature-inspired, faded palettes to keep the page calm and readable.
    private static let palette: [IntentionCardVariation] = [
        IntentionCardVariation(topColor: Color(red: 0.93, green: 0.96, blue: 0.92), bottomColor: Color(red: 0.89, green: 0.93, blue: 0.87), borderColor: Color(red: 0.78, green: 0.85, blue: 0.75).opacity(0.35)),
        IntentionCardVariation(topColor: Color(red: 0.94, green: 0.93, blue: 0.89), bottomColor: Color(red: 0.90, green: 0.88, blue: 0.83), borderColor: Color(red: 0.83, green: 0.79, blue: 0.70).opacity(0.35)),
        IntentionCardVariation(topColor: Color(red: 0.92, green: 0.94, blue: 0.96), bottomColor: Color(red: 0.87, green: 0.90, blue: 0.94), borderColor: Color(red: 0.72, green: 0.79, blue: 0.86).opacity(0.35)),
        IntentionCardVariation(topColor: Color(red: 0.95, green: 0.92, blue: 0.93), bottomColor: Color(red: 0.91, green: 0.87, blue: 0.89), borderColor: Color(red: 0.84, green: 0.73, blue: 0.76).opacity(0.35)),
        IntentionCardVariation(topColor: Color(red: 0.93, green: 0.95, blue: 0.90), bottomColor: Color(red: 0.88, green: 0.91, blue: 0.85), borderColor: Color(red: 0.76, green: 0.82, blue: 0.70).opacity(0.35))
    ]
    
    /// Stable hash keeps each intention on the same color between renders.
    static func forId(_ id: String) -> IntentionCardVariation {
        let hash = id.unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult &+ Int(scalar.value)
        }
        let index = abs(hash) % palette.count
        return palette[index]
    }
}

// MARK: - Record Intentions Pill CTA Style

/// Compact pill button style for Record Intentions: red gradient, soft shadow, centered.
/// Kept local to EditIntentionsView; minimal scope per constraints.
private struct RecordIntentionsPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold)) // readable but not oversized
            .padding(.horizontal, 24) // horizontal padding for pill shape
            .padding(.vertical, 14) // vertical padding; compact but tappable
            .background(
                // Subtle red gradient (not neon); vertical wash for depth
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.75, green: 0.28, blue: 0.28),   // lighter red
                        Color(red: 0.6, green: 0.2, blue: 0.2)        // deeper red
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Capsule()) // pill/oval shape
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4) // soft lift shadow
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Recording + parsing UI placed above the manual intentions list. // describes helper view purpose
private struct RecordIntentionsSection: View { // encapsulates record flow UI
    @ObservedObject private var recorder = CheckInRecorderService.shared // reuse shared recorder to match existing pipeline
    @State private var phase: Phase = .idle // tracks UI state machine
    @State private var transcript: String = "" // holds latest transcript text
    @State private var parsedIntentions: [ParsedIntention] = [] // holds parsed intentions preview
    @State private var errorMessage: String? // holds error text for display
    
    let onIntentionsParsed: ([ParsedIntention]) -> Void // callback to push parsed intentions into drafts
    
    private enum Phase { // defines UI states
        case idle // not recording or processing
        case recording // actively recording audio
        case transcribing // waiting for transcription
        case parsing // waiting for LLM parse
        case preview // showing parsed intentions
        case error // showing an error message
    } // end enum
    
    var body: some View { // builds the section UI
        VStack(spacing: 10) { // compact vertical stack; reduced padding
            VStack(spacing: 8) {
                Text("Example: 20 push-ups") // single short example; daily by default per spec
                    .font(.footnote)
                    .foregroundColor(.secondary)
                stateBlock // CTA or phase-specific UI
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .padding(.bottom, 4)
        }
    } // end body
    
    @ViewBuilder private var stateBlock: some View { // chooses UI per phase
        switch phase { // evaluate current phase
        case .idle: idleView // show record button
        case .recording: recordingView // show stop and timer
        case .transcribing: processingView(text: "Transcribing…") // show spinner
        case .parsing: processingView(text: "Creating intentions…") // show spinner
        case .preview: previewView // show parsed list
        case .error: errorView // show error message
        } // end switch
    } // end stateBlock
    
    private var idleView: some View { // compact centered pill CTA
        Button(action: { startRecording() }) {
            Label("Record Intentions", systemImage: "mic.fill")
                .foregroundStyle(.white) // ensure readability on red gradient
        }
        .buttonStyle(RecordIntentionsPillStyle()) // red gradient, pill, soft shadow
    } // end idleView
    
    private var recordingView: some View { // recording UI
        HStack(spacing: 12) { // horizontal layout
            VStack(alignment: .leading, spacing: 4) { // text stack
                Text("Listening…") // status text
                    .font(.subheadline) // style
                Text("Elapsed: \(formattedElapsed)") // show elapsed timer
                    .font(.caption) // smaller font
                    .foregroundColor(.secondary) // subtle color
            }
            Spacer() // push stop button to trailing edge
            Button(role: .destructive, action: { Task { await stopAndProcess() } }) { // stop and process on tap
                Label("Stop", systemImage: "stop.fill") // stop label
            }
            .buttonStyle(.bordered) // bordered style for clarity
        }
    } // end recordingView
    
    private func processingView(text: String) -> some View { // shared spinner view
        HStack(spacing: 8) { // horizontal layout
            ProgressView() // spinner
            Text(text) // status text
        }
    } // end processingView
    
    private var previewView: some View { // preview UI for parsed intentions
        VStack(alignment: .leading, spacing: 8) { // stack for content
            if parsedIntentions.isEmpty { // handle empty parse
                Text("No intentions found. You can try again or use manual entry.") // empty-state message
                    .font(.footnote) // small font
                    .foregroundColor(.secondary) // subtle color
            } else { // show parsed items
                ForEach(Array(parsedIntentions.enumerated()), id: \.offset) { _, item in // iterate with stable id
                    VStack(alignment: .leading, spacing: 4) { // item display
                        Text(item.title) // show title
                            .font(.body) // standard font
                        Text("\(Int(item.target ?? 1)) \(item.unit ?? "times")") // show target + unit with defaults
                            .font(.caption) // small font
                            .foregroundColor(.secondary) // subtle color
                        if let category = item.category { // optional category display
                            Text("Category: \(category)") // category label
                                .font(.caption2) // tiny font
                                .foregroundColor(.secondary) // subtle color
                        }
                    }
                    .padding(8) // padding around card
                    .background(Color.gray.opacity(0.08)) // light background for separation
                    .cornerRadius(8) // rounded corners
                }
            }
            HStack { // action buttons
                Button(action: { addParsedIntentions() }) { // add parsed to drafts
                    Label("Add intentions", systemImage: "checkmark.circle.fill") // label with check icon
                }
                .buttonStyle(.borderedProminent) // primary style
                
                Button(action: { resetAll() }) { // discard preview
                    Label("Discard", systemImage: "xmark.circle") // discard label
                }
                .buttonStyle(.bordered) // secondary style
            }
        }
    } // end previewView
    
    private var errorView: some View { // error display UI
        VStack(alignment: .leading, spacing: 8) { // stack for error content
            Text(errorMessage ?? "Something went wrong.") // show error text
                .foregroundColor(.red) // red to signal error
            HStack { // action row
                Button(action: { resetAll() }) { // reset to try again
                    Label("Try again", systemImage: "arrow.clockwise") // retry label
                }
                .buttonStyle(.borderedProminent) // primary style
                
                Button(action: { resetAll() }) { // manual entry fallback just resets
                    Label("Use manual entry", systemImage: "square.and.pencil") // manual entry label
                }
                .buttonStyle(.bordered) // secondary style
            }
        }
    } // end errorView
    
    private var formattedElapsed: String { // formats elapsed seconds for display
        let mins = recorder.elapsedSec / 60 // compute minutes
        let secs = recorder.elapsedSec % 60 // compute seconds remainder
        return String(format: "%d:%02d", mins, secs) // format as mm:ss
    } // end formattedElapsed
    
    private func startRecording() { // begins recording flow
        errorMessage = nil // clear previous errors
        parsedIntentions = [] // clear previous parse
        transcript = "" // clear previous transcript
        do { // attempt to start recording
            _ = try recorder.startRecording() // start using shared recorder
            phase = .recording // update phase to recording
        } catch { // handle errors
            errorMessage = error.localizedDescription // capture error text
            phase = .error // move to error state
        }
    } // end startRecording
    
    private func stopAndProcess() async { // stops recording and processes transcript
        guard let result = recorder.stopRecording() else { return } // stop and get audio URL
        phase = .transcribing // move to transcribing state
        let worker = TranscriptionWorker() // create transcription worker
        do { // perform transcription + parsing
            let text = try await worker.transcribeFile(url: result.audioURL, sessionId: "intentions-record", segmentIndex: 0) // transcribe audio file
            transcript = text // store transcript
            phase = .parsing // move to parsing state
            let parsed = try await IntentionsParserService.parse(transcript: text) // call LLM parser
            parsedIntentions = parsed // store parsed intentions
            errorMessage = nil // clear errors
            phase = .preview // show preview
        } catch { // handle failures
            errorMessage = error.localizedDescription // store error text
            phase = .error // show error state
        }
    } // end stopAndProcess
    
    private func addParsedIntentions() { // handles Add button tap
        onIntentionsParsed(parsedIntentions) // send parsed intentions to parent
        resetAll() // reset UI back to idle
    } // end addParsedIntentions
    
    private func resetAll() { // resets state to idle
        parsedIntentions = [] // clear parsed items
        transcript = "" // clear transcript
        errorMessage = nil // clear errors
        phase = .idle // return to idle
    } // end resetAll
} // end RecordIntentionsSection

#Preview {
    EditIntentionsView()
}
