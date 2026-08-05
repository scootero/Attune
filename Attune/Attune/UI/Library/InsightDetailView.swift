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
            Text("What Attune captured")
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

        if isHidden || titleChanged || typeChanged || categoriesChanged || !cleanNote.isEmpty {
            let updated = ItemCorrection(
                itemId: item.id,
                isIncorrect: isHidden,
                correctedTitle: titleChanged ? cleanTitle : nil,
                correctedType: typeChanged ? editedType : nil,
                correctedCategories: categoriesChanged ? Array(editedCategories).sorted() : nil,
                note: cleanNote.isEmpty ? nil : cleanNote
            )
            do {
                try CorrectionsStore.shared.setCorrection(updated)
                correction = updated
            } catch {
                AppLogger.log(AppLogger.ERR, "Capture correction save failed item=\(AppLogger.shortId(item.id))")
            }
        } else if correction != nil {
            do {
                try CorrectionsStore.shared.deleteCorrection(itemId: item.id)
                correction = nil
            } catch {
                AppLogger.log(AppLogger.ERR, "Capture correction delete failed item=\(AppLogger.shortId(item.id))")
            }
        }
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
