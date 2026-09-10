//
//  EngagementDiagnosticsView.swift
//  Pondera
//
//  Debug-only inspection for local, content-free engagement totals.
//

#if DEBUG
import StoreKit
import SwiftUI

struct EngagementDiagnosticsView: View {
    @Environment(\.requestReview) private var requestReview
    @State private var snapshot = EngagementMetricsStore.shared.loadSnapshot()

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var isReviewEligible: Bool {
        EngagementMetricsStore.shared.isReviewEligible(currentVersion: currentVersion)
    }

    var body: some View {
        List {
            Section("Overview") {
                metricRow("Installed", snapshot.installedAt.formatted(date: .abbreviated, time: .omitted))
                metricRow("Active days retained", snapshot.activeDayCount)
                metricRow("Check-In days", snapshot.checkInDayCount)
                metricRow("Data location", "On this iPhone only")
            }

            Section {
                metricRow("Current version", currentVersion)
                metricRow("Eligible now", isReviewEligible ? "Yes" : "No")
                metricRow("Request attempts", snapshot.review.requestAttempts)
                metricRow("Last requested version", snapshot.review.lastRequestedVersion ?? "Never")
                if let lastRequestDate = snapshot.review.lastRequestDate {
                    metricRow("Last request", lastRequestDate.formatted(date: .abbreviated, time: .shortened))
                }

                Button("Preview Apple Review Prompt") {
                    requestReview()
                }
            } header: {
                Text("App Store Review")
            } footer: {
                Text("Development builds can preview Apple’s system prompt. This test button does not change automatic eligibility. TestFlight does not display the prompt.")
            }

            Section("Lifetime Activity") {
                metricRow("App opens", snapshot.lifetime.appOpens)
                metricRow("Intentions created", snapshot.lifetime.intentionsCreated)
                metricRow("Intentions edited", snapshot.lifetime.intentionsEdited)
                metricRow("Intentions archived", snapshot.lifetime.intentionsArchived)
                metricRow("Manual progress updates", snapshot.lifetime.manualProgressUpdates)
                metricRow("Voice progress updates", snapshot.lifetime.voiceProgressUpdates)
                metricRow("Check-Ins started", snapshot.lifetime.checkInsStarted)
                metricRow("Check-Ins completed", snapshot.lifetime.checkInsCompleted)
                metricRow("Check-Ins failed", snapshot.lifetime.checkInsFailed)
                metricRow("Talk sessions started", snapshot.lifetime.talkSessionsStarted)
                metricRow("Talk sessions completed", snapshot.lifetime.talkSessionsCompleted)
                metricRow("Talk sessions failed", snapshot.lifetime.talkSessionsFailed)
                metricRow("Insights created", snapshot.lifetime.insightsCreated)
            }

            if !recentDays.isEmpty {
                Section("Recent Daily Activity") {
                    ForEach(recentDays, id: \.key) { day in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(day.key)
                                .font(.subheadline.weight(.semibold))
                            Text(dailySummary(day.value))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button("Refresh") {
                    snapshot = EngagementMetricsStore.shared.loadSnapshot()
                }
            } footer: {
                Text("Counts and dates only. Pondera does not place transcripts, intention names, quotes, moods, or other personal content in this file.")
            }
        }
        .navigationTitle("Engagement Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            snapshot = EngagementMetricsStore.shared.loadSnapshot()
        }
    }

    private var recentDays: [(key: String, value: EngagementCounters)] {
        snapshot.daily
            .filter { $0.value.hasActivity }
            .sorted { $0.key > $1.key }
            .prefix(14)
            .map { (key: $0.key, value: $0.value) }
    }

    private func dailySummary(_ counters: EngagementCounters) -> String {
        var parts: [String] = []
        if counters.checkInsCompleted > 0 { parts.append("\(counters.checkInsCompleted) Check-In") }
        if counters.manualProgressUpdates + counters.voiceProgressUpdates > 0 {
            parts.append("\(counters.manualProgressUpdates + counters.voiceProgressUpdates) progress")
        }
        if counters.talkSessionsCompleted > 0 { parts.append("\(counters.talkSessionsCompleted) Talk") }
        if counters.insightsCreated > 0 { parts.append("\(counters.insightsCreated) Insights") }
        if counters.intentionsCreated + counters.intentionsEdited + counters.intentionsArchived > 0 {
            parts.append("\(counters.intentionsCreated + counters.intentionsEdited + counters.intentionsArchived) intention changes")
        }
        return parts.isEmpty ? "App opened" : parts.joined(separator: " · ")
    }

    private func metricRow(_ title: String, _ value: Int) -> some View {
        metricRow(title, String(value))
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
#endif
