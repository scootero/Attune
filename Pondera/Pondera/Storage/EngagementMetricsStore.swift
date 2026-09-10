//
//  EngagementMetricsStore.swift
//  Pondera
//
//  Local-only, content-free engagement counters used for diagnostics and the
//  App Store review request. Nothing in this file is uploaded.
//

import Foundation

struct EngagementCounters: Codable, Equatable {
    var appOpens = 0
    var intentionsCreated = 0
    var intentionsEdited = 0
    var intentionsArchived = 0
    var manualProgressUpdates = 0
    var voiceProgressUpdates = 0
    var checkInsStarted = 0
    var checkInsCompleted = 0
    var checkInsFailed = 0
    var talkSessionsStarted = 0
    var talkSessionsCompleted = 0
    var talkSessionsFailed = 0
    var insightsCreated = 0

    var hasActivity: Bool {
        appOpens > 0
            || intentionsCreated > 0
            || intentionsEdited > 0
            || intentionsArchived > 0
            || manualProgressUpdates > 0
            || voiceProgressUpdates > 0
            || checkInsStarted > 0
            || checkInsCompleted > 0
            || checkInsFailed > 0
            || talkSessionsStarted > 0
            || talkSessionsCompleted > 0
            || talkSessionsFailed > 0
            || insightsCreated > 0
    }

    mutating func add(_ event: EngagementEvent, quantity: Int) {
        let value = max(0, quantity)
        switch event {
        case .appOpened: appOpens += value
        case .intentionCreated: intentionsCreated += value
        case .intentionEdited: intentionsEdited += value
        case .intentionArchived: intentionsArchived += value
        case .manualProgressUpdated: manualProgressUpdates += value
        case .voiceProgressUpdated: voiceProgressUpdates += value
        case .checkInStarted: checkInsStarted += value
        case .checkInCompleted: checkInsCompleted += value
        case .checkInFailed: checkInsFailed += value
        case .talkSessionStarted: talkSessionsStarted += value
        case .talkSessionCompleted: talkSessionsCompleted += value
        case .talkSessionFailed: talkSessionsFailed += value
        case .insightCreated: insightsCreated += value
        }
    }
}

enum EngagementEvent: String, Codable {
    case appOpened
    case intentionCreated
    case intentionEdited
    case intentionArchived
    case manualProgressUpdated
    case voiceProgressUpdated
    case checkInStarted
    case checkInCompleted
    case checkInFailed
    case talkSessionStarted
    case talkSessionCompleted
    case talkSessionFailed
    case insightCreated
}

struct ReviewPromptMetrics: Codable, Equatable {
    var lastRequestedVersion: String?
    var lastRequestDate: Date?
    var requestAttempts = 0
}

struct EngagementMetricsSnapshot: Codable, Equatable {
    var schemaVersion = 1
    var installedAt: Date
    var lastUpdatedAt: Date
    var lifetime = EngagementCounters()
    var daily: [String: EngagementCounters] = [:]
    var review = ReviewPromptMetrics()
    var processedEventIDs: [String] = []

    var activeDayCount: Int {
        daily.values.filter(\.hasActivity).count
    }

    var checkInDayCount: Int {
        daily.values.filter { $0.checkInsCompleted > 0 }.count
    }
}

enum AppReviewEligibilityPolicy {
    static let minimumInstallAgeDays = 7
    static let minimumCompletedCheckIns = 4
    static let minimumCheckInDays = 3
    static let minimumDaysBetweenRequests = 14

    static func isEligible(
        snapshot: EngagementMetricsSnapshot,
        currentVersion: String,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard !currentVersion.isEmpty,
              snapshot.lifetime.checkInsCompleted >= minimumCompletedCheckIns,
              snapshot.checkInDayCount >= minimumCheckInDays,
              snapshot.review.lastRequestedVersion != currentVersion else {
            return false
        }

        let installAge = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: snapshot.installedAt),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        guard installAge >= minimumInstallAgeDays else { return false }

        if let lastRequestDate = snapshot.review.lastRequestDate {
            let requestAge = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: lastRequestDate),
                to: calendar.startOfDay(for: now)
            ).day ?? 0
            guard requestAge >= minimumDaysBetweenRequests else { return false }
        }

        return true
    }
}

@MainActor
final class EngagementMetricsStore {
    static let shared = EngagementMetricsStore()

    private static let retainedDailyBuckets = 90
    private static let retainedProcessedEventIDs = 500
    private static var recordedLaunchForCurrentProcess = false

    private let fileURL: URL
    private let now: () -> Date
    private let calendar: Calendar

    init(
        fileURL: URL? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileURL = fileURL ?? AppPaths.engagementMetricsFileURL
        self.calendar = calendar
        self.now = now
    }

    func recordAppLaunchOnce() {
        guard !Self.recordedLaunchForCurrentProcess else { return }
        Self.recordedLaunchForCurrentProcess = true
        record(.appOpened)
    }

    func record(
        _ event: EngagementEvent,
        quantity: Int = 1,
        eventID: String? = nil,
        at date: Date? = nil
    ) {
        guard quantity > 0 else { return }
        var snapshot = loadSnapshot()
        if let eventID, snapshot.processedEventIDs.contains(eventID) {
            return
        }

        let eventDate = date ?? now()
        snapshot.lifetime.add(event, quantity: quantity)
        let key = dateKey(for: eventDate)
        var dailyCounters = snapshot.daily[key] ?? EngagementCounters()
        dailyCounters.add(event, quantity: quantity)
        snapshot.daily[key] = dailyCounters
        snapshot.lastUpdatedAt = eventDate

        if let eventID {
            snapshot.processedEventIDs.append(eventID)
            if snapshot.processedEventIDs.count > Self.retainedProcessedEventIDs {
                snapshot.processedEventIDs.removeFirst(snapshot.processedEventIDs.count - Self.retainedProcessedEventIDs)
            }
        }

        pruneDailyBuckets(in: &snapshot)
        save(snapshot)
    }

    func loadSnapshot() -> EngagementMetricsSnapshot {
        guard let data = try? Data(contentsOf: fileURL) else {
            return emptySnapshot()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(EngagementMetricsSnapshot.self, from: data)) ?? emptySnapshot()
    }

    func claimReviewRequestIfEligible(currentVersion: String) -> Bool {
        var snapshot = loadSnapshot()
        let requestDate = now()
        guard AppReviewEligibilityPolicy.isEligible(
            snapshot: snapshot,
            currentVersion: currentVersion,
            now: requestDate,
            calendar: calendar
        ) else {
            return false
        }

        snapshot.review.lastRequestedVersion = currentVersion
        snapshot.review.lastRequestDate = requestDate
        snapshot.review.requestAttempts += 1
        snapshot.lastUpdatedAt = requestDate
        save(snapshot)
        return true
    }

    func isReviewEligible(currentVersion: String, at date: Date? = nil) -> Bool {
        AppReviewEligibilityPolicy.isEligible(
            snapshot: loadSnapshot(),
            currentVersion: currentVersion,
            now: date ?? now(),
            calendar: calendar
        )
    }

    private func emptySnapshot() -> EngagementMetricsSnapshot {
        let date = now()
        return EngagementMetricsSnapshot(installedAt: date, lastUpdatedAt: date)
    }

    private func dateKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func pruneDailyBuckets(in snapshot: inout EngagementMetricsSnapshot) {
        let sortedKeys = snapshot.daily.keys.sorted()
        guard sortedKeys.count > Self.retainedDailyBuckets else { return }
        for key in sortedKeys.prefix(sortedKeys.count - Self.retainedDailyBuckets) {
            snapshot.daily.removeValue(forKey: key)
        }
    }

    private func save(_ snapshot: EngagementMetricsSnapshot) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            AppLogger.log(AppLogger.ERR, "Engagement metrics save failed error=\"\(error.localizedDescription)\"")
        }
    }
}
