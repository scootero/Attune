//
//  TopicDetailView.swift
//  Attune
//
//  Detail view for a single topic showing metadata and all occurrences.
//  Resolves item IDs from topic.itemIds using orphan-safe ItemResolver.
//

import SwiftUI

struct TopicDetailView: View {
    /// The topic to display
    let topic: TopicAggregate
    
    /// Resolved occurrences (items) for this topic
    @State private var occurrences: [ExtractedItem] = []
    
    /// Corrections loaded from store
    @State private var corrections: [String: ItemCorrection] = [:]
    
    var body: some View {
        List {
            // Section 1: Topic Metadata
            Section("Topic Summary") {
                // Display title
                LabeledContent("Title", value: topic.displayTitle)
                
                // Occurrence count
                LabeledContent("Mentions", value: "\(topic.occurrenceCount)")
                
                // First seen
                LabeledContent("First Seen", value: formatDate(topic.firstSeenAtISO))
                
                // Last seen
                LabeledContent("Last Seen", value: formatDate(topic.lastSeenAtISO))
                
                // Categories
                if !topic.categories.isEmpty {
                    LabeledContent("Categories", value: formatCategories(topic.categories))
                }
                
                // Canonical key (debug info, subtle)
                LabeledContent("Key", value: topic.canonicalKey)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Section 2: Occurrences
            Section("Occurrences (\(occurrences.count))") {
                if occurrences.isEmpty {
                    // Empty state (shouldn't happen, but handle gracefully)
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("No occurrences found")
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(occurrences) { item in
                        NavigationLink(destination: InsightDetailView(item: item)) {
                            OccurrenceRow(item: item, correction: corrections[item.id])
                        }
                    }
                }
            }
        }
        .navigationTitle("Topic")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadOccurrences()
            loadCorrections()
        }
    }
    
    /// Loads occurrences by resolving item IDs (orphan-safe)
    private func loadOccurrences() {
        // Use ItemResolver for efficient, orphan-safe resolution
        let resolvedItems = ItemResolver.resolveItems(itemIds: topic.itemIds)
        
        // Sort by createdAt descending (newest first)
        occurrences = resolvedItems.sorted { $0.createdAt > $1.createdAt }
    }
    
    /// Loads corrections from store
    private func loadCorrections() {
        corrections = CorrectionsStore.shared.loadCorrections()
    }
    
    /// Formats ISO8601 timestamp as human-readable date
    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        
        guard let date = formatter.date(from: isoString) else {
            return isoString
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        return dateFormatter.string(from: date)
    }
    
    /// Formats categories for display
    private func formatCategories(_ categories: [String]) -> String {
        categories.map { category in
            category.replacingOccurrences(of: "_", with: " ")
                .capitalized
        }.joined(separator: ", ")
    }
}

/// Row view for a single occurrence in the TopicDetailView
struct OccurrenceRow: View {
    let item: ExtractedItem
    let correction: ItemCorrection?
    
    /// Computed corrected view
    private var correctedView: CorrectedItemView {
        item.applyingCorrection(correction)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Type badge and date
            HStack {
                TypeBadge(type: correctedView.displayType)
                
                Spacer()
                
                // Show correction indicator
                if correctedView.isMarkedIncorrect {
                    Label("Incorrect", systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                } else if correction != nil {
                    Label("Corrected", systemImage: "pencil.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                
                Text(formatDate(item.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Source quote
            Text("\"\(item.sourceQuote)\"")
                .font(.subheadline)
                .italic()
                .lineLimit(3)
            
            // Session provenance
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.caption)
                Text("\(shortId(item.sessionId)) • seg \(item.segmentIndex)")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    /// Returns a short ID (first 6 characters) for display
    private func shortId(_ id: String) -> String {
        String(id.prefix(6))
    }
    
    /// Formats ISO8601 timestamp as human-readable date
    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        
        guard let date = formatter.date(from: isoString) else {
            return "recently"
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        
        return dateFormatter.string(from: date)
    }
}

#Preview {
    NavigationView {
        TopicDetailView(
            topic: TopicAggregate(
                canonicalKey: "exercise__abc123",
                displayTitle: "Exercise",
                firstSeenAtISO: ISO8601DateFormatter().string(from: Date()),
                categories: ["fitness_health"],
                itemId: "sample-id"
            )
        )
    }
}
