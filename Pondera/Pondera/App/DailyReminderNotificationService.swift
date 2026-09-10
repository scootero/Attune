//
//  DailyReminderNotificationService.swift
//  Pondera
//
//  Schedules an actionable local reminder when no intention progress was updated.
//

import Foundation
@preconcurrency import UserNotifications

enum DailyReminderCopy {
    static let title = "Pondera — Let’s make some progress"

    static func body(intentionTitles: [String]) -> String {
        let titles = intentionTitles.prefix(2)
        guard !titles.isEmpty else { return "Choose an intention to move forward." }
        return "What would you like to move forward? \(titles.joined(separator: " • "))"
    }

    static func followUpBody(intentionTitle: String?) -> String {
        guard let intentionTitle, !intentionTitle.isEmpty else {
            return "Ready to update one of today’s intentions?"
        }
        return "Ready to update \(intentionTitle)?"
    }
}

enum DailyReminderPolicy {
    static func shouldNotify(
        hasActiveIntentions: Bool,
        progressEntryCount: Int,
        manualProgressUpdateCount: Int
    ) -> Bool {
        hasActiveIntentions && progressEntryCount == 0 && manualProgressUpdateCount == 0
    }
}

extension Notification.Name {
    static let ponderaDailyReminderRouteRequested = Notification.Name("attune.daily.reminder.route.requested")
}

@MainActor
final class DailyReminderNotificationService {
    static let shared = DailyReminderNotificationService()

    // Keep the existing request identifier so upgrades replace the old reminder.
    private let reminderRequestId = "attune.daily.reminder"
    private let followUpRequestId = "attune.daily.reminder.follow-up"
    private let primaryCategoryId = "attune.daily.reminder.category"
    private let followUpCategoryId = "attune.daily.reminder.follow-up.category"
    private let actionPrefix = "attune.daily.reminder.update."
    private let followUpActionId = "attune.daily.reminder.follow-up.update"
    private let notificationCenter = UNUserNotificationCenter.current()
    private(set) var pendingRoute: ReminderNotificationRoute?

    private init() {}

    func refreshReminderForToday(now: Date = Date()) {
        guard ReminderPreferences.isReminderEnabled else {
            removeAllPendingReminders()
            return
        }

        guard let context = reminderContext(now: now), context.shouldNotify else {
            removeAllPendingReminders()
            return
        }

        let intentions = Array(context.intentions.prefix(2))
        let reminderTime = ReminderPreferences.reminderTimeComponents
        registerCategories(for: intentions)

        let requestId = reminderRequestId
        let center = notificationCenter
        let categoryId = primaryCategoryId
        notificationCenter.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = DailyReminderCopy.title
            content.body = DailyReminderCopy.body(intentionTitles: intentions.map(\.title))
            content.sound = .default
            content.categoryIdentifier = categoryId
            if let first = intentions.first {
                content.userInfo = [ReminderNotificationRoute.intentionIdKey: first.id]
            }

            let components = DateComponents(
                hour: reminderTime.hour ?? 14,
                minute: reminderTime.minute ?? 0
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: requestId, content: content, trigger: trigger)

            center.removePendingNotificationRequests(withIdentifiers: [requestId])
            center.add(request)
        }
    }

    func handleNotificationResponse(_ response: UNNotificationResponse) {
        let requestIdentifier = response.notification.request.identifier
        guard requestIdentifier == reminderRequestId || requestIdentifier == followUpRequestId else { return }

        let intentionId = intentionId(
            actionIdentifier: response.actionIdentifier,
            userInfo: response.notification.request.content.userInfo
        )
        let isPrimaryReminder = requestIdentifier == reminderRequestId
        pendingRoute = ReminderNotificationRoute(
            intentionId: intentionId,
            showsFollowUpConfirmation: isPrimaryReminder
        )

        if isPrimaryReminder, reminderContext(now: Date())?.shouldNotify == true {
            scheduleOneHourFollowUp(intentionId: intentionId)
        } else {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [followUpRequestId])
        }

        NotificationCenter.default.post(name: .ponderaDailyReminderRouteRequested, object: nil)
    }

    func consumePendingRoute() -> ReminderNotificationRoute? {
        defer { pendingRoute = nil }
        return pendingRoute
    }

    private func reminderContext(now: Date) -> (intentions: [Intention], shouldNotify: Bool)? {
        guard let intentionSet = try? IntentionSetStore.shared.loadOrCreateCurrentIntentionSet() else { return nil }
        let intentions = IntentionStore.shared.loadIntentions(ids: intentionSet.intentionIds).filter(\.isActive)
        let dateKey = ProgressCalculator.dateKey(for: now)
        let entries = ProgressStore.shared.loadEntries(dateKey: dateKey, intentionSetId: intentionSet.id)
        let manualUpdates = OverrideStore.shared.loadOverrideRecordsForDate(dateKey: dateKey)
        return (
            intentions,
            DailyReminderPolicy.shouldNotify(
                hasActiveIntentions: !intentions.isEmpty,
                progressEntryCount: entries.count,
                manualProgressUpdateCount: manualUpdates.count
            )
        )
    }

    private func scheduleOneHourFollowUp(intentionId: String?) {
        let intention = intentionId.flatMap { IntentionStore.shared.loadIntention(id: $0) }

        let content = UNMutableNotificationContent()
        content.title = "Pondera — How did it go?"
        content.body = DailyReminderCopy.followUpBody(intentionTitle: intention?.title)
        content.sound = .default
        content.categoryIdentifier = followUpCategoryId
        if let intentionId {
            content.userInfo = [ReminderNotificationRoute.intentionIdKey: intentionId]
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60 * 60, repeats: false)
        let request = UNNotificationRequest(identifier: followUpRequestId, content: content, trigger: trigger)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [followUpRequestId])
        notificationCenter.add(request)
    }

    private func registerCategories(for intentions: [Intention]) {
        let primaryActions = intentions.prefix(2).map { intention in
            UNNotificationAction(
                identifier: actionPrefix + intention.id,
                title: intention.title,
                options: [.foreground]
            )
        }
        let followUpAction = UNNotificationAction(
            identifier: followUpActionId,
            title: "Update progress",
            options: [.foreground]
        )
        let primary = UNNotificationCategory(
            identifier: primaryCategoryId,
            actions: primaryActions,
            intentIdentifiers: [],
            options: []
        )
        let followUp = UNNotificationCategory(
            identifier: followUpCategoryId,
            actions: [followUpAction],
            intentIdentifiers: [],
            options: []
        )

        let primaryCategoryId = primaryCategoryId
        let followUpCategoryId = followUpCategoryId
        let center = notificationCenter
        notificationCenter.getNotificationCategories { existing in
            var categories = existing.filter {
                $0.identifier != primaryCategoryId && $0.identifier != followUpCategoryId
            }
            categories.insert(primary)
            categories.insert(followUp)
            center.setNotificationCategories(categories)
        }
    }

    private func intentionId(actionIdentifier: String, userInfo: [AnyHashable: Any]) -> String? {
        if actionIdentifier.hasPrefix(actionPrefix) {
            let value = String(actionIdentifier.dropFirst(actionPrefix.count))
            return value.isEmpty ? nil : value
        }
        return userInfo[ReminderNotificationRoute.intentionIdKey] as? String
    }

    private func removeAllPendingReminders() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [reminderRequestId, followUpRequestId])
    }

}

struct ReminderNotificationRoute: Equatable {
    static let intentionIdKey = "intentionId"
    let intentionId: String?
    let showsFollowUpConfirmation: Bool
}

/// Schedules local reminders for timed event captures shown in Pondera's Calendar.
/// Notification authorization is intentionally never requested here; Settings owns
/// that explicit user action.
@MainActor
final class CalendarEventNotificationService {
    static let shared = CalendarEventNotificationService()

    private let notificationCenter = UNUserNotificationCenter.current()
    private let requestPrefix = "attune.calendar.event."
    private let categoryIdentifier = "attune.calendar.event.category"
    private let itemIDKey = "calendarItemId"
    private let maximumEvents = 32 // iOS allows at most 64 pending local requests.

    private init() {}

    func refresh(now: Date = Date()) {
        guard ReminderPreferences.areCalendarEventRemindersEnabled else {
            removePendingEventRequests()
            return
        }
        let items = ExtractionStore.shared.loadAllExtractions()
        let corrections = CorrectionsStore.shared.loadCorrections()
        let captures = CalendarCaptureParser.captures(from: items, corrections: corrections)
            .filter { !$0.isAllDay && $0.hasSpecifiedTime && $0.start > now }
            .sorted { $0.start < $1.start }
            .prefix(maximumEvents)

        let center = notificationCenter
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

            center.getPendingNotificationRequests { pending in
                let oldIDs = pending.map(\.identifier).filter { $0.hasPrefix(self.requestPrefix) }
                center.removePendingNotificationRequests(withIdentifiers: oldIDs)

                let requests = captures.flatMap { self.requests(for: $0, now: now) }
                for request in requests {
                    center.add(request)
                }
            }
        }
    }

    func isCalendarNotification(_ notification: UNNotification) -> Bool {
        notification.request.identifier.hasPrefix(requestPrefix)
    }

    private func removePendingEventRequests() {
        notificationCenter.getPendingNotificationRequests { pending in
            let IDs = pending.map(\.identifier).filter { $0.hasPrefix(self.requestPrefix) }
            self.notificationCenter.removePendingNotificationRequests(withIdentifiers: IDs)
        }
    }

    private func requests(for capture: CalendarCapture, now: Date) -> [UNNotificationRequest] {
        let body = "\(capture.title) starts \(capture.start.formatted(date: .omitted, time: .shortened))."
        let reminderTimes: [(String, Date)] = [
            ("hour", capture.start.addingTimeInterval(-60 * 60)),
            ("now", capture.start)
        ].filter { $0.1 > now }

        return reminderTimes.map { kind, date in
            let content = UNMutableNotificationContent()
            content.title = kind == "hour" ? "Pondera — In 1 hour" : "Pondera — Starting now"
            content.body = body
            content.sound = .default
            content.categoryIdentifier = categoryIdentifier
            content.userInfo = [itemIDKey: capture.item.id]

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, date.timeIntervalSinceNow),
                repeats: false
            )
            return UNNotificationRequest(
                identifier: "\(requestPrefix)\(capture.item.id).\(kind)",
                content: content,
                trigger: trigger
            )
        }
    }
}
