//
//  CheckInsListView.swift
//  Attune
//
//  List of check-ins with day separators (Today, Yesterday, date).
//  Newest-first; row shows time + 2-line transcript snippet.
//

import SwiftUI

struct CheckInsListView: View {
    /// Check-ins to display (should already be sorted newest-first)
    let checkIns: [CheckIn]
    
    /// Optional navigation title (e.g., "Today Check-ins" or "Check-ins")
    var title: String = "Check-ins"
    
    var body: some View {
        Group {
            if checkIns.isEmpty {
                emptyState
            } else {
                checkInsList
            }
        }
        .navigationTitle(title)
    }
    
    /// Empty state when no check-ins
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No check-ins yet")
                .font(.headline)
            Text("Record a check-in from the Home tab")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    /// List grouped by day with separators
    private var checkInsList: some View {
        List {
            ForEach(dayGroups, id: \.dateKey) { group in
                Section(header: Text(group.headerLabel).font(.subheadline).fontWeight(.medium)) {
                    ForEach(group.checkIns) { checkIn in
                        NavigationLink(destination: CheckInDetailView(checkInId: checkIn.id)) {
                            checkInRow(checkIn)
                        }
                    }
                }
            }
        }
    }
    
    /// Single row: time + 2-line transcript snippet
    private func checkInRow(_ checkIn: CheckIn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Time (e.g., 2:30 PM)
            Text(checkIn.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.subheadline)
                .fontWeight(.medium)
            // Transcript snippet: max 2 lines, ellipsized
            Text(transcriptSnippet(for: checkIn))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
    
    /// Returns first ~120 chars of transcript + ellipsis if longer
    private func transcriptSnippet(for checkIn: CheckIn) -> String {
        let text = checkIn.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "No transcript" }
        let prefix = String(text.prefix(120)).trimmingCharacters(in: .whitespaces)
        return prefix + (text.count > 120 ? "…" : "")
    }
    
    /// Day-grouped check-ins for section headers (Today, Yesterday, or formatted date)
    private var dayGroups: [CheckInDayGroup] {
        let todayKey = ProgressCalculator.dateKey(for: Date())
        let calendar = Calendar.current
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let yesterdayKey = ProgressCalculator.dateKey(for: yesterdayDate)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy"
        
        var groups: [String: [CheckIn]] = [:]
        for checkIn in checkIns {
            let key = ProgressCalculator.dateKey(for: checkIn.createdAt)
            groups[key, default: []].append(checkIn)
        }
        
        // Sort each group newest-first (check-ins in group already newest-first from input)
        for key in groups.keys {
            groups[key]?.sort { $0.createdAt > $1.createdAt }
        }
        
        // Build ordered groups: Today first, then Yesterday, then others by date desc
        var result: [CheckInDayGroup] = []
        let sortedKeys = groups.keys.sorted { a, b in
            if a == todayKey { return true }
            if b == todayKey { return false }
            if a == yesterdayKey { return true }
            if b == yesterdayKey { return false }
            return a > b
        }
        
        for key in sortedKeys {
            guard let items = groups[key], !items.isEmpty else { continue }
            let headerLabel: String
            if key == todayKey {
                headerLabel = "Today"
            } else if key == yesterdayKey {
                headerLabel = "Yesterday"
            } else {
                // Parse dateKey to format
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = TimeZone.current
                if let date = formatter.date(from: key) {
                    headerLabel = dateFormatter.string(from: date)
                } else {
                    headerLabel = key
                }
            }
            result.append(CheckInDayGroup(dateKey: key, headerLabel: headerLabel, checkIns: items))
        }
        return result
    }
}

/// Helper for day grouping: dateKey + header label + check-ins for that day
private struct CheckInDayGroup {
    let dateKey: String
    let headerLabel: String
    let checkIns: [CheckIn]
}

#Preview {
    NavigationView {
        CheckInsListView(
            checkIns: [],
            title: "Today Check-ins"
        )
    }
}
