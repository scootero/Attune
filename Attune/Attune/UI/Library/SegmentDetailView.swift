//
//  SegmentDetailView.swift
//  Attune
//
//  Shows segment metadata, transcript, and audio file status.
//

import SwiftUI

struct SegmentDetailView: View {
    /// Session and segment IDs to load
    let sessionId: String
    let segmentId: String
    
    /// Loaded session and segment
    @State private var session: Session?
    @State private var segment: Segment?
    
    var body: some View {
        Group {
            if let session = session, let segment = segment {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Segment metadata
                        SegmentMetadataSection(session: session, segment: segment)
                        
                        Divider()
                        
                        // Transcript
                        TranscriptSection(segment: segment)
                        
                        Divider()
                        
                        // Insights from this segment
                        InsightsFromSegmentSection(session: session, segment: segment)
                    }
                    .padding()
                }
                .navigationTitle("Segment \(segment.index)")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                // Loading or not found
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    
                    Text("Segment Not Found")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            loadSegment()
        }
    }
    
    /// Loads the segment from disk
    private func loadSegment() {
        guard let loadedSession = SessionStore.shared.loadSession(id: sessionId) else {
            return
        }
        
        session = loadedSession
        segment = loadedSession.segments.first { $0.id == segmentId }
    }
}

// MARK: - Segment Metadata Section

struct SegmentMetadataSection: View {
    let session: Session
    let segment: Segment
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Segment Info")
                .font(.headline)
            
            MetadataRow(label: "Session", value: session.shortId)
            MetadataRow(label: "Segment Index", value: "\(segment.index)")
            MetadataRow(label: "ID", value: segment.id)
            MetadataRow(label: "Status", value: segment.status)
            MetadataRow(label: "Started", value: segment.startedAt.formatted(date: .abbreviated, time: .shortened))
            
            if let endedAt = segment.endedAt {
                MetadataRow(label: "Ended", value: endedAt.formatted(date: .abbreviated, time: .shortened))
                
                let duration = endedAt.timeIntervalSince(segment.startedAt)
                MetadataRow(label: "Duration", value: String(format: "%.1fs", duration))
            }
            
            // Audio file info
            MetadataRow(label: "Audio File", value: segment.audioFileName)
            
            let audioExists = AppPaths.audioFileExists(sessionId: session.id, audioFileName: segment.audioFileName)
            HStack {
                Text("Audio Present:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    Image(systemName: audioExists ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(audioExists ? .green : .red)
                    Text(audioExists ? "Yes" : "No")
                        .fontWeight(.medium)
                }
                .font(.caption)
            }
            
            if let deletedAt = segment.audioDeletedAt {
                MetadataRow(label: "Audio Deleted", value: deletedAt.formatted(date: .abbreviated, time: .shortened))
            }
            
            // Error if present
            if let error = segment.error {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Error:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
    }
}

// MARK: - Transcript Section

struct TranscriptSection: View {
    let segment: Segment
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript")
                .font(.headline)
            
            if let transcript = segment.transcriptText, !transcript.isEmpty {
                Text(transcript)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            } else {
                Text("No transcript yet")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
        }
    }
}

// MARK: - Insights From Segment Section

struct InsightsFromSegmentSection: View {
    let session: Session
    let segment: Segment
    
    /// Loaded insights for this segment
    @State private var insights: [ExtractedItem] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Insights from this segment")
                .font(.headline)
            
            if insights.isEmpty {
                Text("No insights from this segment.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            } else {
                ForEach(insights) { item in
                    NavigationLink(destination: InsightDetailView(item: item)) {
                        VStack(alignment: .leading, spacing: 6) {
                            // Title and type badge
                            HStack {
                                Text(item.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .lineLimit(2)
                                
                                Spacer()
                                
                                TypeBadge(type: item.type)
                            }
                            
                            // Categories
                            if !item.categories.isEmpty {
                                Text(formatCategories(item.categories))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            // Confidence
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                                Text(formatPercentage(item.confidence))
                            }
                            .font(.caption)
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            loadInsights()
        }
    }
    
    /// Loads insights for this specific segment
    private func loadInsights() {
        insights = ExtractionStore.shared.loadExtractions(sessionId: session.id, segmentId: segment.id)
    }
    
    /// Formats categories for display (e.g., "fitness_health" -> "Fitness Health")
    private func formatCategories(_ categories: [String]) -> String {
        categories.map { category in
            category.replacingOccurrences(of: "_", with: " ")
                .capitalized
        }.joined(separator: ", ")
    }
    
    /// Formats a confidence value as percentage (e.g., 0.78 -> "78%")
    private func formatPercentage(_ value: Double) -> String {
        "\(Int(value * 100))%"
    }
}

#Preview {
    NavigationView {
        SegmentDetailView(sessionId: "test-session-id", segmentId: "test-segment-id")
    }
}
