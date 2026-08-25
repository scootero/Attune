//
//  InsightDetailView.swift
//  Attune
//
//  Consumer detail for a stored extracted item. Technical extraction metadata
//  remains in logs/debug storage, not in the primary experience.
//

import SwiftUI

struct InsightDetailView: View {
    let item: ExtractedItem

    @State private var correction: ItemCorrection?
    @State private var showingReviewSheet = false

    private var corrected: CorrectedItemView { item.applyingCorrection(correction) }

    var body: some View {
        ZStack {
            AttuneScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    captureHeader
                    summaryCard

                    if CalendarFeature.isEnabled,
                       corrected.displayType == ExtractedItem.ItemType.event {
                        scheduleCard
                    }

                    if !item.sourceQuote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sourceCard
                    }

                    if let note = corrected.correctionNote, !note.isEmpty {
                        noteCard(note)
                    }

                    trackingClarification
                }
                .padding(.horizontal, AttuneTheme.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Capture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Review") { showingReviewSheet = true }
            }
        }
        .sheet(isPresented: $showingReviewSheet) {
            CaptureReviewSheet(item: item, correction: $correction)
        }
        .onAppear {
            correction = CorrectionsStore.shared.getCorrection(itemId: item.id)
        }
    }

    private var captureHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TypeBadge(type: corrected.displayType)
                Spacer()
                if corrected.isMarkedIncorrect {
                    Label("Hidden", systemImage: "eye.slash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AttuneTheme.textTertiary)
                }
            }

            Text(corrected.displayTitle)
                .font(.title2.bold())
                .foregroundStyle(corrected.isMarkedIncorrect ? AttuneTheme.textSecondary : AttuneTheme.textPrimary)

            HStack {
                Text(InsightDisplay.fullDate(item.createdAt))
                if let category = corrected.displayCategories.first {
                    Text("·")
                    Label(InsightDisplay.categoryLabel(category), systemImage: InsightDisplay.categoryIcon(category))
                }
            }
            .font(.caption)
            .foregroundStyle(AttuneTheme.textSecondary)
        }
        .padding(16)
        .attuneCard()
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("What Pondera captured")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AttuneTheme.textPrimary)
            Text(item.summary.isEmpty ? corrected.displayTitle : item.summary)
                .font(.body)
                .foregroundStyle(AttuneTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .attuneCard()
    }

    private var scheduleCard: some View {
        let capture = CalendarCaptureParser.capture(for: item, correction: correction)
        return VStack(alignment: .leading, spacing: 8) {
            Label("Calendar", systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AttuneTheme.textPrimary)

            if let capture {
                Text(capture.start.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AttuneTheme.textPrimary)
                Text(scheduleTimeLabel(capture))
                    .font(.subheadline)
                    .foregroundStyle(AttuneTheme.textSecondary)
            } else {
                Text("Needs a date and time")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AttuneTheme.warning)
                Text("Tap Review to schedule this capture.")
                    .font(.subheadline)
                    .foregroundStyle(AttuneTheme.textSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .attuneCard()
    }

    private func scheduleTimeLabel(_ capture: CalendarCapture) -> String {
        guard capture.hasSpecifiedTime else { return "Time not specified" }
        let start = capture.start.formatted(date: .omitted, time: .shortened)
        guard let end = capture.end, end > capture.start else { return start }
        return "\(start)–\(end.formatted(date: .omitted, time: .shortened))"
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("From your words")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AttuneTheme.textPrimary)
            Text("“\(item.sourceQuote)”")
                .font(.body)
                .italic()
                .foregroundStyle(AttuneTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .attuneCard()
    }

    private func noteCard(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Your note")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AttuneTheme.textPrimary)
            Text(note)
                .font(.body)
                .foregroundStyle(AttuneTheme.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .attuneCard()
    }

    private var trackingClarification: some View {
        Label {
            Text(corrected.displayType == ExtractedItem.ItemType.intention
                 ? "Captured intention—not yet added to Today’s tracked progress."
                 : "This capture does not change Today’s tracked progress.")
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.caption)
        .foregroundStyle(AttuneTheme.textTertiary)
        .padding(.horizontal, 4)
    }
}

struct CaptureReviewSheet: View {
    let item: ExtractedItem
    @Binding var correction: ItemCorrection?

    @Environment(\.dismiss) private var dismiss
    @State private var isHidden: Bool
    @State private var editedTitle: String
    @State private var editedType: String
    @State private var editedCategories: Set<String>
    @State private var note: String
    @State private var isScheduled: Bool
    @State private var scheduledDate: Date
    @State private var hasSpecifiedTime: Bool
    @State private var startTime: Date
    @State private var hasEndTime: Bool
    @State private var endTime: Date
    @State private var scheduleWasEdited = false

    private let availableTypes = [
        ExtractedItem.ItemType.event,
        ExtractedItem.ItemType.intention,
        ExtractedItem.ItemType.commitment,
        ExtractedItem.ItemType.state
    ]

    private let availableCategories = [
        ExtractedItem.Category.fitnessHealth,
        ExtractedItem.Category.careerWork,
        ExtractedItem.Category.moneyFinance,
        ExtractedItem.Category.personalGrowth,
        ExtractedItem.Category.relationshipsSocial,
        ExtractedItem.Category.stressLoad,
        ExtractedItem.Category.peaceWellbeing
    ]

    init(item: ExtractedItem, correction: Binding<ItemCorrection?>) {
        self.item = item
        _correction = correction
        let existing = correction.wrappedValue
        _isHidden = State(initialValue: existing?.isIncorrect ?? false)
        _editedTitle = State(initialValue: existing?.correctedTitle ?? item.title)
        _editedType = State(initialValue: existing?.correctedType ?? item.type)
        _editedCategories = State(initialValue: Set(existing?.correctedCategories ?? item.categories))
        _note = State(initialValue: existing?.note ?? "")

        let capture = CalendarCaptureParser.capture(for: item, correction: existing)
        let capturedAt = CalendarCaptureParser.parseDate(item.createdAt) ?? Date()
        let initialStart = capture?.start ?? capturedAt
        _isScheduled = State(initialValue: capture != nil)
        _scheduledDate = State(initialValue: initialStart)
        _hasSpecifiedTime = State(initialValue: capture?.hasSpecifiedTime ?? false)
        _startTime = State(initialValue: initialStart)
        _hasEndTime = State(initialValue: capture?.end != nil)
        _endTime = State(initialValue: capture?.end ?? Calendar.current.date(byAdding: .hour, value: 1, to: initialStart) ?? initialStart)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Hide from Insights", isOn: $isHidden)
                } footer: {
                    Text("Hidden captures no longer appear in Recent captures or theme counts.")
                }

                Section("Capture") {
                    TextField("Title", text: $editedTitle)

                    Picker("Type", selection: $editedType) {
                        ForEach(availableTypes, id: \.self) { type in
                            Label(InsightDisplay.typeLabel(type), systemImage: InsightDisplay.typeIcon(type))
                                .tag(type)
                        }
                    }
                }


                if CalendarFeature.isEnabled,
                   editedType == ExtractedItem.ItemType.event {
                    Section {
                        Toggle("Show on Calendar", isOn: editedBinding($isScheduled))

                        if isScheduled {
                            DatePicker(
                                "Date",
                                selection: editedBinding($scheduledDate),
                                displayedComponents: .date
                            )

                            Toggle("Specific time", isOn: editedBinding($hasSpecifiedTime))

                            if hasSpecifiedTime {
                                DatePicker(
                                    "Starts",
                                    selection: editedBinding($startTime),
                                    displayedComponents: .hourAndMinute
                                )

                                Toggle("End time", isOn: editedBinding($hasEndTime))
                                if hasEndTime {
                                    DatePicker(
                                        "Ends",
                                        selection: editedBinding($endTime),
                                        displayedComponents: .hourAndMinute
                                    )
                                }
                            }
                        }
                    } header: {
                        Text("Calendar")
                    } footer: {
                        Text("A time without a spoken date is scheduled on the recording day. You can change or remove it here.")
                    }
                }

                Section("Categories") {
                    ForEach(availableCategories, id: \.self) { category in
                        Toggle(
                            InsightDisplay.categoryLabel(category),
                            isOn: Binding(
                                get: { editedCategories.contains(category) },
                                set: { selected in
                                    if selected {
                                        editedCategories.insert(category)
                                    } else {
                                        editedCategories.remove(category)
                                    }
                                }
                            )
                        )
                    }
                }

                Section("Personal note") {
                    TextEditor(text: $note)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Review Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCorrection()
                        dismiss()
                    }
                    .disabled(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveCorrection() {
        let cleanTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleChanged = cleanTitle != item.title
        let typeChanged = editedType != item.type
        let categoriesChanged = Set(item.categories) != editedCategories
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendarSchedule = scheduleCorrection()

        if isHidden || titleChanged || typeChanged || categoriesChanged || !cleanNote.isEmpty || calendarSchedule != nil {
            let updated = ItemCorrection(
                itemId: item.id,
                isIncorrect: isHidden,
                correctedTitle: titleChanged ? cleanTitle : nil,
                correctedType: typeChanged ? editedType : nil,
                correctedCategories: categoriesChanged ? Array(editedCategories).sorted() : nil,
                note: cleanNote.isEmpty ? nil : cleanNote,
                calendarSchedule: calendarSchedule
            )
            do {
                try CorrectionsStore.shared.setCorrection(updated)
                correction = updated
                AttuneHaptics.saved()
            } catch {
                AppLogger.log(AppLogger.ERR, "Capture correction save failed item=\(AppLogger.shortId(item.id))")
                AttuneHaptics.error()
            }
        } else if correction != nil {
            do {
                try CorrectionsStore.shared.deleteCorrection(itemId: item.id)
                correction = nil
                AttuneHaptics.saved()
            } catch {
                AppLogger.log(AppLogger.ERR, "Capture correction delete failed item=\(AppLogger.shortId(item.id))")
                AttuneHaptics.error()
            }
        }
    }

    private func editedBinding<Value>(_ binding: Binding<Value>) -> Binding<Value> {
        Binding(
            get: { binding.wrappedValue },
            set: { value in
                binding.wrappedValue = value
                scheduleWasEdited = true
            }
        )
    }

    private func scheduleCorrection() -> CalendarScheduleCorrection? {
        guard editedType == ExtractedItem.ItemType.event else {
            if item.type == ExtractedItem.ItemType.event,
               (scheduleWasEdited || correction?.calendarSchedule != nil) {
                return CalendarScheduleCorrection(
                    isScheduled: false,
                    startISO8601: nil,
                    endISO8601: nil,
                    hasSpecifiedTime: false
                )
            }
            return nil
        }

        guard scheduleWasEdited else { return correction?.calendarSchedule }
        guard isScheduled else {
            return CalendarScheduleCorrection(
                isScheduled: false,
                startISO8601: nil,
                endISO8601: nil,
                hasSpecifiedTime: false
            )
        }

        guard hasSpecifiedTime else {
            return CalendarScheduleCorrection(
                isScheduled: true,
                startISO8601: localDayString(scheduledDate),
                endISO8601: nil,
                hasSpecifiedTime: false
            )
        }

        let start = combining(day: scheduledDate, time: startTime)
        let end = hasEndTime ? combining(day: scheduledDate, time: endTime) : nil
        return CalendarScheduleCorrection(
            isScheduled: true,
            startISO8601: ISO8601DateFormatter().string(from: start),
            endISO8601: end.map { ISO8601DateFormatter().string(from: $0) },
            hasSpecifiedTime: true
        )
    }

    private func combining(day: Date, time: Date) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        let timeParts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(
            bySettingHour: timeParts.hour ?? 0,
            minute: timeParts.minute ?? 0,
            second: 0,
            of: day
        ) ?? day
    }

    private func localDayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        InsightDetailView(
            item: ExtractedItem(
                sessionId: "sample-session",
                segmentId: "sample-segment",
                segmentIndex: 0,
                type: ExtractedItem.ItemType.intention,
                title: "Get back to morning workouts",
                summary: "You want to rebuild a consistent morning workout routine.",
                categories: [ExtractedItem.Category.fitnessHealth],
                confidence: 0.9,
                strength: 0.8,
                sourceQuote: "I really want to start working out in the mornings again.",
                fingerprint: "sample"
            )
        )
    }
}
