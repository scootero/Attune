//
//  TopicsListView.swift
//  Attune
//
//  List of aggregated topics, showing occurrence counts and last mentioned time.
//  Topics are loaded from Topics.json and sorted by most recently mentioned.
//

import SwiftUI

struct TopicsListView: View {
    /// All topic aggregates loaded from disk
    @State private var topics: [TopicAggregate] = []
    
    var body: some View {
        Group {
            if topics.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "folder")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    
                    Text("No Topics Yet")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Topics will appear here as you mention things across sessions")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // List of topics
                List {
                    ForEach(topics) { topic in
                        NavigationLink(destination: TopicDetailView(topic: topic)) {
                            VStack(alignment: .leading, spacing: 6) {
                                // Title and occurrence count
                                HStack {
                                    Text(topic.displayTitle)
                                        .font(.headline)
                                        .lineLimit(2)
                                    
                                    Spacer()
                                    
                                    // Occurrence count badge
                                    Text("\(topic.occurrenceCount)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.2))
                                        .foregroundColor(.blue)
                                        .cornerRadius(8)
                                }
                                
                                // Categories
                                if !topic.categories.isEmpty {
                                    Text(formatCategories(topic.categories))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                // Last mentioned time
                                HStack {
                                    Image(systemName: "clock")
                                        .font(.caption)
                                    Text("Last mentioned \(formatRelativeTime(topic.lastSeenAtISO))")
                                        .font(.caption)
                                }
                                .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .onAppear {
            loadTopics()
        }
        .refreshable {
            loadTopics()
        }
    }
    
    /// Loads all topics from disk and sorts by last seen (newest first)
    private func loadTopics() {
        let topicsDict = TopicAggregateStore.shared.loadTopics()
        
        // Convert to array and sort by lastSeenAtISO descending
        topics = Array(topicsDict.values).sorted { topic1, topic2 in
            // ISO8601 string comparison works for sorting
            topic1.lastSeenAtISO > topic2.lastSeenAtISO
        }
    }
    
    /// Formats categories for display (e.g., "fitness_health" -> "Fitness Health")
    private func formatCategories(_ categories: [String]) -> String {
        categories.map { category in
            category.replacingOccurrences(of: "_", with: " ")
                .capitalized
        }.joined(separator: ", ")
    }
    
    /// Formats ISO8601 timestamp as relative time (e.g., "2 hours ago")
    private func formatRelativeTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        
        guard let date = formatter.date(from: isoString) else {
            return "recently"
        }
        
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        // Format relative time
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        } else {
            let weeks = Int(interval / 604800)
            return "\(weeks) week\(weeks == 1 ? "" : "s") ago"
        }
    }
}

#Preview {
    NavigationView {
        TopicsListView()
    }
}
