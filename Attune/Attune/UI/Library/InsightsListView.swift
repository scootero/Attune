//
//  InsightsListView.swift
//  Attune
//
//  List of all extracted items (insights) across all sessions.
//  Supports two views: All (flat timeline) and Topics (grouped).
//

import SwiftUI

struct InsightsListView: View {
    /// Selected tab: All or Topics
    @State private var selectedTab: InsightsTab = .all
    
    /// All extracted items loaded from disk (for All tab)
    @State private var items: [ExtractedItem] = []
    
    /// Corrections loaded from store
    @State private var corrections: [String: ItemCorrection] = [:]
    
    var body: some View {
        VStack(spacing: 0) {
            // Segmented picker at top
            Picker("View", selection: $selectedTab) {
                Text("All").tag(InsightsTab.all)
                Text("Topics").tag(InsightsTab.topics)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content based on selected tab
            if selectedTab == .all {
                AllItemsView(items: $items, corrections: $corrections)
            } else {
                TopicsListView()
            }
        }
        .onAppear {
            loadItems()
            loadCorrections()
        }
        .refreshable {
            loadItems()
            loadCorrections()
        }
    }
    
    /// Loads all extracted items from disk
    private func loadItems() {
        items = ExtractionStore.shared.loadAllExtractions()
    }
    
    /// Loads corrections from store
    private func loadCorrections() {
        corrections = CorrectionsStore.shared.loadCorrections()
    }
}

/// Represents the two tabs in Insights view
enum InsightsTab {
    case all
    case topics
}

/// View showing all items as a flat timeline
struct AllItemsView: View {
    @Binding var items: [ExtractedItem]
    @Binding var corrections: [String: ItemCorrection]
    
    var body: some View {
        Group {
            if items.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    
                    Text("No Insights Yet")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Insights will appear here after segments are processed")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // List of insights
                List {
                    ForEach(items) { item in
                        let correction = corrections[item.id]
                        let correctedView = item.applyingCorrection(correction)
                        
                        NavigationLink(destination: InsightDetailView(item: item)) {
                            VStack(alignment: .leading, spacing: 6) {
                                // Title and type badge
                                HStack {
                                    Text(correctedView.displayTitle)
                                        .font(.headline)
                                        .lineLimit(2)
                                        .foregroundColor(correctedView.isMarkedIncorrect ? .secondary : .primary)
                                    
                                    Spacer()
                                    
                                    TypeBadge(type: correctedView.displayType)
                                    
                                    // Correction indicator
                                    if correctedView.isMarkedIncorrect {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                            .font(.caption)
                                    } else if correction != nil {
                                        Image(systemName: "pencil.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                    }
                                }
                                
                                // Topic key (subtle UI cue)
                                Text(formatTopicKey(item.fingerprint))
                                    .font(.caption2)
                                    .foregroundColor(.secondary.opacity(0.7))
                                    .lineLimit(1)
                                
                                // Categories (corrected)
                                if !correctedView.displayCategories.isEmpty {
                                    Text(formatCategories(correctedView.displayCategories))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                // Confidence and strength
                                HStack(spacing: 12) {
                                    Label(formatPercentage(item.confidence), systemImage: "checkmark.circle")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    
                                    Label(formatPercentage(item.strength), systemImage: "bolt.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                                
                                // Provenance: session shortId + segment index
                                Text("\(shortId(item.sessionId)) • seg \(item.segmentIndex)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                            .opacity(correctedView.isMarkedIncorrect ? 0.5 : 1.0)
                        }
                    }
                }
            }
        }
    }
    
    /// Formats the topic key (fingerprint) for subtle display
    /// Shows just the stem part without the hash
    private func formatTopicKey(_ fingerprint: String) -> String {
        // Extract stem from "stem__hash" format
        let components = fingerprint.components(separatedBy: "__")
        guard let stem = components.first else {
            return fingerprint
        }
        
        // Convert stem to readable format
        return "topic: " + stem.replacingOccurrences(of: "_", with: " ")
    }
    
    /// Returns a short ID (first 6 characters) for display
    private func shortId(_ id: String) -> String {
        String(id.prefix(6))
    }
    
    /// Formats categories for display (e.g., "fitness_health" -> "Fitness Health")
    private func formatCategories(_ categories: [String]) -> String {
        categories.map { category in
            category.replacingOccurrences(of: "_", with: " ")
                .capitalized
        }.joined(separator: ", ")
    }
    
    /// Formats a confidence or strength value as percentage (e.g., 0.78 -> "78%")
    private func formatPercentage(_ value: Double) -> String {
        "\(Int(value * 100))%"
    }
}

/// Type badge view for extracted items
struct TypeBadge: View {
    let type: String
    
    var body: some View {
        Text(type.capitalized)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(4)
    }
    
    /// Color based on type
    private var backgroundColor: Color {
        switch type {
        case ExtractedItem.ItemType.event:
            return .purple
        case ExtractedItem.ItemType.intention:
            return .blue
        case ExtractedItem.ItemType.commitment:
            return .orange
        case ExtractedItem.ItemType.state:
            return .green
        default:
            return .gray
        }
    }
}

#Preview {
    NavigationView {
        InsightsListView()
    }
}
