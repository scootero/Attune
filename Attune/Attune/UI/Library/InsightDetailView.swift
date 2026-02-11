//
//  InsightDetailView.swift
//  Attune
//
//  Shows full details of an extracted item including provenance and metadata.
//

import SwiftUI

struct InsightDetailView: View {
    /// The extracted item to display
    let item: ExtractedItem
    
    /// Current correction loaded from store
    @State private var correction: ItemCorrection?
    
    /// Edit sheet state
    @State private var showingEditSheet = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Corrections section (if any exist)
                if correction != nil {
                    CorrectionsSection(item: item, correction: $correction)
                    Divider()
                }
                
                // Item info section
                ItemInfoSection(item: item, correction: correction)
                
                Divider()
                
                // Review status section
                ReviewStatusSection(item: item)
                
                Divider()
                
                // Provenance section
                ProvenanceSection(item: item)
                
                Divider()
                
                // Metadata section
                MetadataSection(item: item)
            }
            .padding()
        }
        .navigationTitle("Insight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") {
                    showingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            CorrectionEditSheet(item: item, correction: $correction)
        }
        .onAppear {
            loadCorrection()
        }
    }
    
    /// Loads correction from store
    private func loadCorrection() {
        correction = CorrectionsStore.shared.getCorrection(itemId: item.id)
    }
}

// MARK: - Corrections Section

struct CorrectionsSection: View {
    let item: ExtractedItem
    @Binding var correction: ItemCorrection?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("User Corrections")
                    .font(.headline)
                
                Spacer()
                
                if correction?.isIncorrect == true {
                    Label("Marked Incorrect", systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                } else {
                    Label("Corrected", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            // Show what was corrected
            if let correctedTitle = correction?.correctedTitle {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Corrected Title:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(correctedTitle)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
            }
            
            if let correctedType = correction?.correctedType {
                HStack {
                    Text("Corrected Type:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TypeBadge(type: correctedType)
                }
            }
            
            if let correctedCategories = correction?.correctedCategories {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Corrected Categories:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatCategories(correctedCategories))
                        .font(.body)
                        .foregroundColor(.green)
                }
            }
            
            if let note = correction?.note, !note.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Note:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(note)
                        .font(.caption)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.05))
        .cornerRadius(12)
    }
    
    /// Formats categories for display
    private func formatCategories(_ categories: [String]) -> String {
        categories.map { category in
            category.replacingOccurrences(of: "_", with: " ")
                .capitalized
        }.joined(separator: ", ")
    }
}

// MARK: - Item Info Section

struct ItemInfoSection: View {
    let item: ExtractedItem
    let correction: ItemCorrection?
    
    /// Computed corrected view
    private var correctedView: CorrectedItemView {
        item.applyingCorrection(correction)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Item Info")
                    .font(.headline)
                
                Spacer()
                
                // Show if displaying original AI values
                if correction == nil {
                    Label("AI Generated", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            // Title (with strikethrough if corrected)
            VStack(alignment: .leading, spacing: 4) {
                Text("Title:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if correction?.correctedTitle != nil {
                    Text(item.title)
                        .font(.body)
                        .strikethrough()
                        .foregroundColor(.secondary)
                }
                
                Text(correctedView.displayTitle)
                    .font(.body)
                    .fontWeight(.medium)
            }
            
            // Type (with strikethrough if corrected)
            HStack {
                Text("Type:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if correction?.correctedType != nil {
                    TypeBadge(type: item.type)
                        .opacity(0.5)
                }
                
                TypeBadge(type: correctedView.displayType)
            }
            
            // Categories (with strikethrough if corrected)
            if !item.categories.isEmpty || !correctedView.displayCategories.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Categories:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if correction?.correctedCategories != nil {
                        Text(formatCategories(item.categories))
                            .font(.body)
                            .strikethrough()
                            .foregroundColor(.secondary)
                    }
                    
                    Text(formatCategories(correctedView.displayCategories))
                        .font(.body)
                }
            }
            
            // Summary
            VStack(alignment: .leading, spacing: 4) {
                Text("Summary:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(item.summary)
                    .font(.body)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
            
            // Confidence and strength
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Confidence:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                        Text(formatPercentage(item.confidence))
                            .fontWeight(.medium)
                    }
                    .font(.body)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Strength:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.orange)
                        Text(formatPercentage(item.strength))
                            .fontWeight(.medium)
                    }
                    .font(.body)
                }
            }
        }
    }
    
    /// Formats categories for display
    private func formatCategories(_ categories: [String]) -> String {
        categories.map { category in
            category.replacingOccurrences(of: "_", with: " ")
                .capitalized
        }.joined(separator: ", ")
    }
    
    /// Formats a value as percentage
    private func formatPercentage(_ value: Double) -> String {
        "\(Int(value * 100))%"
    }
}

// MARK: - Review Status Section

struct ReviewStatusSection: View {
    let item: ExtractedItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Review Status")
                .font(.headline)
            
            HStack {
                Text("Status:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ReviewStateBadge(state: item.reviewState)
            }
            
            if let reviewedAt = item.reviewedAt {
                HStack {
                    Text("Reviewed:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatDate(reviewedAt))
                        .font(.caption)
                }
            }
        }
    }
    
    /// Formats ISO8601 date string for display
    private func formatDate(_ iso8601String: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: iso8601String) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return iso8601String
    }
}

/// Review state badge view
struct ReviewStateBadge: View {
    let state: String
    
    var body: some View {
        Text(state.capitalized)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(4)
    }
    
    /// Color based on review state
    private var backgroundColor: Color {
        switch state {
        case ExtractedItem.ReviewState.new:
            return .blue
        case ExtractedItem.ReviewState.confirmed:
            return .green
        case ExtractedItem.ReviewState.rejected:
            return .red
        case ExtractedItem.ReviewState.edited:
            return .orange
        default:
            return .gray
        }
    }
}

// MARK: - Provenance Section

struct ProvenanceSection: View {
    let item: ExtractedItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Provenance")
                .font(.headline)
            
            // Source quote
            VStack(alignment: .leading, spacing: 4) {
                Text("You said:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\"\(item.sourceQuote)\"")
                    .font(.body)
                    .italic()
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }
            
            // Context before
            if let contextBefore = item.contextBefore, !contextBefore.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Context before:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(contextBefore)
                        .font(.caption)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            // Context after
            if let contextAfter = item.contextAfter, !contextAfter.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Context after:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(contextAfter)
                        .font(.caption)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
    }
}

// MARK: - Metadata Section

struct MetadataSection: View {
    let item: ExtractedItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metadata")
                .font(.headline)
            
            MetadataRow(label: "Session", value: shortId(item.sessionId))
            MetadataRow(label: "Segment Index", value: "\(item.segmentIndex)")
            MetadataRow(label: "Item ID", value: item.id)
            MetadataRow(label: "Fingerprint", value: item.fingerprint)
            MetadataRow(label: "Created", value: formatDate(item.createdAt))
            MetadataRow(label: "Captured", value: formatDate(item.extractedAt))
        }
    }
    
    /// Returns a short ID (first 6 characters) for display
    private func shortId(_ id: String) -> String {
        String(id.prefix(6))
    }
    
    /// Formats ISO8601 date string for display
    private func formatDate(_ iso8601String: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: iso8601String) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return iso8601String
    }
}

// MARK: - Correction Edit Sheet

struct CorrectionEditSheet: View {
    let item: ExtractedItem
    @Binding var correction: ItemCorrection?
    
    @Environment(\.dismiss) private var dismiss
    
    // Edit state
    @State private var isIncorrect: Bool
    @State private var editedTitle: String
    @State private var editedType: String
    @State private var editedCategories: Set<String>
    @State private var note: String
    
    // Available options
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
        self._correction = correction
        
        // Initialize state from existing correction or defaults
        if let existing = correction.wrappedValue {
            _isIncorrect = State(initialValue: existing.isIncorrect)
            _editedTitle = State(initialValue: existing.correctedTitle ?? item.title)
            _editedType = State(initialValue: existing.correctedType ?? item.type)
            _editedCategories = State(initialValue: Set(existing.correctedCategories ?? item.categories))
            _note = State(initialValue: existing.note ?? "")
        } else {
            _isIncorrect = State(initialValue: false)
            _editedTitle = State(initialValue: item.title)
            _editedType = State(initialValue: item.type)
            _editedCategories = State(initialValue: Set(item.categories))
            _note = State(initialValue: "")
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Mark incorrect toggle
                Section {
                    Toggle("Mark as incorrect", isOn: $isIncorrect)
                } header: {
                    Text("Correction Status")
                }
                
                // Edit fields
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Original: \(item.title)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("Corrected title", text: $editedTitle)
                            .textFieldStyle(.roundedBorder)
                    }
                } header: {
                    Text("Title")
                } footer: {
                    Text("Edit the title if the AI got it wrong")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Original: \(item.type.capitalized)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Picker("Corrected type", selection: $editedType) {
                            ForEach(availableTypes, id: \.self) { type in
                                Text(type.capitalized).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } header: {
                    Text("Type")
                } footer: {
                    Text("Change the type if needed")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Original: \(formatCategories(item.categories))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ForEach(availableCategories, id: \.self) { category in
                            Toggle(formatCategory(category), isOn: Binding(
                                get: { editedCategories.contains(category) },
                                set: { isSelected in
                                    if isSelected {
                                        editedCategories.insert(category)
                                    } else {
                                        editedCategories.remove(category)
                                    }
                                }
                            ))
                        }
                    }
                } header: {
                    Text("Categories")
                } footer: {
                    Text("Select all categories that apply")
                }
                
                Section {
                    TextEditor(text: $note)
                        .frame(minHeight: 80)
                } header: {
                    Text("Note (Optional)")
                } footer: {
                    Text("Add a note explaining why you made this correction")
                }
            }
            .navigationTitle("Edit Insight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCorrection()
                        dismiss()
                    }
                }
            }
        }
    }
    
    /// Saves the correction
    private func saveCorrection() {
        // Determine what changed
        let titleChanged = editedTitle != item.title
        let typeChanged = editedType != item.type
        let categoriesChanged = Set(item.categories) != editedCategories
        
        // Only save if something changed or isIncorrect is true
        if isIncorrect || titleChanged || typeChanged || categoriesChanged || !note.isEmpty {
            let newCorrection = ItemCorrection(
                itemId: item.id,
                isIncorrect: isIncorrect,
                correctedTitle: titleChanged ? editedTitle : nil,
                correctedType: typeChanged ? editedType : nil,
                correctedCategories: categoriesChanged ? Array(editedCategories).sorted() : nil,
                note: note.isEmpty ? nil : note
            )
            
            do {
                try CorrectionsStore.shared.setCorrection(newCorrection)
                correction = newCorrection
            } catch {
                print("Failed to save correction: \(error)")
            }
        } else {
            // No changes - delete correction if it exists
            if correction != nil {
                do {
                    try CorrectionsStore.shared.deleteCorrection(itemId: item.id)
                    correction = nil
                } catch {
                    print("Failed to delete correction: \(error)")
                }
            }
        }
    }
    
    /// Formats a single category for display
    private func formatCategory(_ category: String) -> String {
        category.replacingOccurrences(of: "_", with: " ").capitalized
    }
    
    /// Formats categories for display
    private func formatCategories(_ categories: [String]) -> String {
        if categories.isEmpty {
            return "None"
        }
        return categories.map { formatCategory($0) }.joined(separator: ", ")
    }
}

#Preview {
    NavigationView {
        InsightDetailView(
            item: ExtractedItem(
                sessionId: "test-session-123",
                segmentId: "test-segment-456",
                segmentIndex: 3,
                type: ExtractedItem.ItemType.event,
                title: "Morning workout planned",
                summary: "User mentioned planning to go to the gym tomorrow morning at 6 AM for a cardio session.",
                categories: [ExtractedItem.Category.fitnessHealth],
                confidence: 0.85,
                strength: 0.72,
                sourceQuote: "I'm going to hit the gym tomorrow morning at 6 for some cardio",
                contextBefore: "I've been feeling sluggish lately.",
                contextAfter: "Need to get back into my routine.",
                fingerprint: "abc123def456"
            )
        )
    }
}
