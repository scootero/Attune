//
//  EditIntentionsView.swift
//  Attune
//
//  Draft editing of intentions (max 10). On Save: ends current IntentionSet,
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
    @State private var draftIntentions: [DraftIntention] = []
    /// True while loading draft from disk on background (avoids blocking main thread)
    @State private var isLoadingDraft = true
    /// Optional status message for record-intentions actions (e.g., cap reached)
    @State private var recordStatusMessage: String?
    /// Stores the draft id selected from swipe-to-delete so alert can confirm intent.
    @State private var pendingDeleteDraftId: String?
    /// Stores a friendly title for the delete confirmation alert message.
    @State private var pendingDeleteDraftTitle: String = ""
    
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
                        RecordIntentionsSection(onIntentionsParsed: { parsed in // injects record flow above manual list
                            let remaining = DraftIntention.maxCount - draftIntentions.count // compute available slots
                            guard remaining > 0 else { // guard when already at cap
                                recordStatusMessage = "You've reached the maximum of \(DraftIntention.maxCount) intentions. Remove one to add more." // user-facing cap message
                                return // exit because nothing can be added
                            } // end guard
                            let toAdd = parsed.prefix(remaining).map { $0.toDraftIntention() } // cap additions and map to drafts
                            draftIntentions.insert(contentsOf: toAdd, at: 0) // insert at top so new recorded intentions appear first
                            if parsed.count > toAdd.count { // detect truncation by cap
                                recordStatusMessage = "Added \(toAdd.count) intentions; reached the cap of \(DraftIntention.maxCount)." // explain partial add
                            } else { // full add path
                                recordStatusMessage = "Added \(toAdd.count) intentions from recording." // success message
                            } // end if
                        }) // end RecordIntentionsSection
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)) // tighter top padding for compact CTA
                        .listRowBackground(Color.clear) // no row background; CTA is self-contained
                        .listRowSeparator(.hidden) // hide separator for cleaner CTA area
                        
                        if let recordStatusMessage { // show status when available
                            Text(recordStatusMessage) // display status text
                                .font(.footnote) // use small font for helper text
                                .foregroundColor(.secondary) // subtle color to avoid clutter
                        } // end optional status
                        
                        ForEach($draftIntentions) { $draft in // iterate editable rows with stable bindings // keeps each row bound directly to its draft model
                            IntentionEditRow( // render the editable row content itself // row now owns its card styling for smoother typing updates
                                draft: $draft, // pass the two-way draft binding into the row // allows instant field edits without extra mapping
                                variation: IntentionCardVariation.forId(draft.id) // pick a stable faded color set from id // prevents color jumping during re-renders
                            )
                                .listRowBackground(Color.clear) // clear list row background since card now draws inside the row // reduces list background composition work
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16)) // keep visible gap between cards // slightly larger separation improves scanability
                                .listRowSeparator(.hidden) // hide separators so card spacing remains clean // avoids visual clutter
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) { // keep explicit swipe-to-delete behavior on each row // matches requested interaction
                                    Button(role: .destructive) {
                                        pendingDeleteDraftId = draft.id // capture which row is pending deletion // used by confirmation alert
                                        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines) // trim title for clean alert copy // avoids weird spacing in prompt
                                        pendingDeleteDraftTitle = trimmedTitle.isEmpty ? "this intention" : "\"\(trimmedTitle)\"" // show fallback when title is empty // keeps prompt user-friendly
                                    } label: {
                                        Label("Delete", systemImage: "trash") // standard destructive affordance label // makes action intent obvious
                                    }
                                }
                        }
                        .transaction { transaction in // tune transaction behavior for this row collection // helps prevent micro-jank while editing text
                            transaction.animation = nil // disable implicit row animations during state changes // reduces per-keystroke layout animation cost
                        }
                        
                        if draftIntentions.count < DraftIntention.maxCount {
                            Button(action: addDraft) {
                                Label("Add Intention", systemImage: "plus.circle.fill")
                            }
                        }
                    }
                    .scrollContentBackground(.hidden) // allow custom background
                    .listStyle(.plain) // plain list keeps spacing predictable and lighter to render while typing
                    .scrollDismissesKeyboard(.interactively) // let drag gestures dismiss keyboard smoothly // reduces abrupt keyboard/layout interactions
                    .background(
                        // Very subtle gradient wash; barely visible, adds depth
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(.systemGroupedBackground),
                                Color(.systemGroupedBackground).opacity(0.94)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    )
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
        draftIntentions.contains { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    
    private func addDraft() {
        guard draftIntentions.count < DraftIntention.maxCount else { return }
        draftIntentions.append(DraftIntention.empty())
    }
    
    private func deleteDraft(at offsets: IndexSet) {
        draftIntentions.remove(atOffsets: offsets)
    }
    
    /// Deletes the draft selected by swipe action after user confirms the alert.
    private func deletePendingDraft() {
        guard let pendingDeleteDraftId else { return }
        draftIntentions.removeAll { $0.id == pendingDeleteDraftId }
        self.pendingDeleteDraftId = nil
        self.pendingDeleteDraftTitle = ""
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
