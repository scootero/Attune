//
//  ProgressView.swift
//  Attune
//
//  Progress tab: Daily Totals (last 7 days) and Per Goal views. Slice 6.
//

import SwiftUI // Import SwiftUI for view definitions

fileprivate enum ProgressTab: String, CaseIterable { // Make enum fileprivate so ProgressContentView can access it within this file
    case dailyTotals = "Daily Totals" // Tab for daily totals list
    case perGoal = "Per Goal" // Tab for per-goal list
}

/// Route value for DayDetail
fileprivate struct DayDetailRoute: Hashable { // Filewide visibility so ProgressContentView can route to day details
    let dateKey: String // Date key identifying the selected day
}

/// Route value for IntentionDetail (uses id to look up from intentionRows)
fileprivate struct IntentionDetailRoute: Hashable { // Filewide visibility so ProgressContentView can route to intention details
    let intentionId: String // Intention identifier used for lookup
}

struct ProgressContentView: View { // Hosts the Progress UI without its own NavigationStack so Library can embed it
    @State private var selectedTab: ProgressTab = .dailyTotals // Track which progress tab is selected
    @State private var dayRows: [DayRow] = [] // Cached daily rows for the Daily Totals tab
    @State private var intentionRows: [IntentionRow] = [] // Cached intention rows for the Per Goal tab
    
    var body: some View { // Main body for the embeddable progress content
        VStack(spacing: 0) { // Stack picker and tab content vertically with no spacing
            Picker("View", selection: $selectedTab) { // Segmented control to switch between tabs
                ForEach(ProgressTab.allCases, id: \.self) { tab in // Iterate through available tabs
                    Text(tab.rawValue).tag(tab) // Label each segment and bind selection
                }
            }
            .pickerStyle(.segmented) // Use segmented control style
            .padding() // Add standard padding around the picker
            
            switch selectedTab { // Render content based on selected tab
            case .dailyTotals: // Daily Totals tab selected
                dailyTotalsContent // Show daily totals list
            case .perGoal: // Per Goal tab selected
                perGoalContent // Show per-goal list
            }
        }
        .navigationTitle("Progress") // Set the navigation title for the embedded content
        .navigationDestination(for: DayDetailRoute.self) { route in // Register destination for day detail navigation
            DayDetailView(dateKey: route.dateKey) // Show day detail for the selected date
        }
        .navigationDestination(for: IntentionDetailRoute.self) { route in // Register destination for intention detail navigation
            IntentionDetailRouteView(intentionId: route.intentionId, intentionRows: intentionRows) // Show intention detail using cached rows
        }
        .onAppear { // Load data when the view appears
            loadData() // Refresh both day and intention rows
        }
    }
    
    // MARK: - Daily Totals
    
    private var dailyTotalsContent: some View { // List showing recent daily totals
        List { // Use List for rows
                ForEach(dayRows) { row in // Iterate through daily rows
                NavigationLink(value: DayDetailRoute(dateKey: row.dateKey)) { // Navigate to day detail on tap
                    HStack { // Layout date and percent horizontally
                        VStack(alignment: .leading, spacing: 4) { // Left column with date and mood
                            Text(formatDate(row.date)) // Display formatted date
                                .font(.headline) // Use headline font for date
                            if let mood = row.moodLabel, !mood.isEmpty { // Only show mood when available
                                Text(mood) // Display mood label
                                    .font(.caption) // Use caption font for mood
                                    .foregroundColor(.secondary) // Secondary color for mood text
                            }
                        }
                        Spacer() // Push percent to the trailing edge
                        Text("\(Int(row.overallPercent * 100))%") // Show overall percent for the day
                            .font(.headline.monospacedDigit()) // Use monospaced digits for alignment
                            .foregroundColor(.secondary) // Secondary color for percent text
                    }
                    .padding(.vertical, 4) // Add vertical padding to the row
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String { // Helper to format dates for list display
        let formatter = DateFormatter() // Create date formatter
        formatter.dateStyle = .medium // Medium date style (e.g., Feb 17, 2026)
        return formatter.string(from: date) // Return formatted date string
    }
    
    // MARK: - Per Goal
    
    private var perGoalContent: some View { // List showing per-goal targets
        Group { // Group to handle empty vs populated states
            if intentionRows.isEmpty { // When no intentions exist
                ContentUnavailableView( // Show empty state view
                    "No intentions", // Title for empty state
                    systemImage: "target", // Icon for empty state
                    description: Text("Add intentions on the Home tab to track progress per goal.") // Guidance text for user
                )
            } else { // When intentions exist
                List { // Show intentions list
                    ForEach(intentionRows) { row in // Iterate through intention rows
                        NavigationLink(value: IntentionDetailRoute(intentionId: row.intention.id)) { // Navigate to intention detail on tap
                            HStack { // Layout title and target
                                Text(row.intention.title) // Show intention title
                                    .font(.body) // Body font for title
                                Spacer() // Push target to trailing edge
                                Text("\(Int(row.intention.targetValue)) \(row.intention.unit)/\(row.intention.timeframe)") // Show target and timeframe
                                    .font(.caption) // Caption font for target
                                    .foregroundColor(.secondary) // Secondary color for target text
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Data
    
    private func loadData() { // Load data for both tabs
        dayRows = ProgressDataHelper.loadDayRows() // Populate day rows from helper
        intentionRows = ProgressDataHelper.loadIntentionRows() // Populate intention rows from helper
    }
}

struct ProgressView: View { // Thin wrapper to host ProgressContentView inside its own NavigationStack when used standalone
    var body: some View { // Body for standalone Progress tab usage
        NavigationStack { // Provide navigation container for the progress screen
            ProgressContentView() // Embed the reusable progress content
        }
    }
}

#Preview { // Preview for Xcode canvas
    ProgressView() // Preview the standalone Progress view
}
