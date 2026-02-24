//
//  DailyReminderNotificationService.swift
//  Attune
//
//  Schedules a daily local reminder at user-selected time when user needs a nudge.
//

import Foundation // Needed for Date, Calendar, and date calculations used by reminder scheduling.
import UserNotifications // Needed for local notification permission checks and scheduling notification requests.

/// Keeps one pending reminder in sync with today's check-in/progress state.
@MainActor // Ensures all store reads happen on main actor because app stores are main-actor isolated.
final class DailyReminderNotificationService {
    
    /// Shared singleton used across UI and app lifecycle hooks.
    static let shared = DailyReminderNotificationService() // Single source of truth for reminder scheduling logic.
    
    /// Stable identifier so we can replace/remove the same pending reminder safely.
    private let reminderRequestId = "attune.daily.reminder" // Constant ID avoids duplicate pending notifications even when time changes.
    
    /// Reuse the system notification center instance for all notification operations.
    private let notificationCenter = UNUserNotificationCenter.current() // Shared iOS notification manager.
    
    /// Prevent external construction to keep scheduling logic centralized.
    private init() {} // Singleton-only initialization.
    
    /// Recomputes today's condition and updates the pending reminder at configured time.
    func refreshReminderForToday(now: Date = Date()) {
        guard ReminderPreferences.isReminderEnabled else { // Respect in-app reminder toggle so users can disable this reminder without system-level changes.
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [reminderRequestId]) // Remove any queued reminder immediately when toggle is off.
            return // Exit because no reminder should be scheduled while disabled.
        }
        
        guard let triggerDate = scheduledReminderDateIfStillUpcoming(reference: now) else { // Only schedule while today's configured reminder time is still in the future.
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [reminderRequestId]) // Remove stale request when today's reminder time has already passed.
            return // Stop because we only schedule for the current day in this version.
        }
        
        let reminderState = buildReminderState(for: now) // Compute whether reminder is needed and what percent text to show.
        guard reminderState.shouldNotify else { // If user already checked in and is >= 50%, no reminder should exist.
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [reminderRequestId]) // Clear pending reminder to avoid false nudges.
            return // Exit early because there is nothing to schedule.
        }
        
        let requestId = reminderRequestId // Copy request identifier into local constant so closure avoids actor-isolated self access.
        let center = notificationCenter // Copy notification center into local constant so closure can use it directly.
        notificationCenter.getNotificationSettings { settings in // Check authorization before creating notification requests.
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return } // Only schedule when notifications are currently allowed.
            
            let content = UNMutableNotificationContent() // Build the visible content for the local reminder.
            content.title = "Attune Check-in Reminder" // Short title shown above body text in notification UI.
            content.body = "You're only at \(reminderState.percent)% of your intentions today. You can do it!" // Motivational body including current completion percentage.
            content.sound = .default // Plays the default notification sound so the user can hear it.
            
            let calendar = Calendar.current // Use local calendar/timezone for trigger construction.
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate) // Pin this reminder to today's configured hour/minute date components.
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false) // Fire once at today's scheduled time.
            let request = UNNotificationRequest(identifier: requestId, content: content, trigger: trigger) // Create replaceable request with stable identifier.
            
            center.removePendingNotificationRequests(withIdentifiers: [requestId]) // Remove prior request before adding updated content/conditions.
            center.add(request) { _ in // Enqueue reminder; tapping notification opens the app by default.
                // Intentionally no-op; failure is safe because reminder is non-critical UX enhancement.
            }
        }
    }
    
    /// Computes whether user still needs a reminder and derives display percent text.
    private func buildReminderState(for now: Date) -> (shouldNotify: Bool, percent: Int) {
        guard let intentionSet = try? IntentionSetStore.shared.loadOrCreateCurrentIntentionSet() else { // If no intention set exists yet, do not notify by default.
            return (false, 0) // Safe default avoids reminders before user has setup data.
        }
        
        let dateKey = ProgressCalculator.dateKey(for: now) // Convert current date into app's local YYYY-MM-DD key.
        let checkIns = CheckInStore.shared.loadCheckIns(intentionSetId: intentionSet.id, dateKey: dateKey) // Load today's check-ins for current intention set.
        let intentions = IntentionStore.shared.loadIntentions(ids: intentionSet.intentionIds).filter { $0.isActive } // Load only active intentions that count toward daily progress.
        let entries = ProgressStore.shared.loadEntries(dateKey: dateKey, intentionSetId: intentionSet.id) // Load today's progress entries for this intention set.
        let overrides = OverrideStore.shared.loadOverridesForDate(dateKey: dateKey) // Load manual override totals that supersede raw entries.
        
        var totalsByIntentionId: [String: Double] = [:] // Build a map of intention -> today's total for overall progress calculation.
        for intention in intentions { // Iterate each active intention to compute its effective total.
            let total = ProgressCalculator.totalForIntention( // Reuse existing progress rules (TOTAL precedence, weekly handling later in percentComplete).
                entries: entries,
                dateKey: dateKey,
                intentionId: intention.id,
                intentionSetId: intentionSet.id,
                overrideAmount: overrides[intention.id]
            )
            totalsByIntentionId[intention.id] = total // Save computed total into lookup dictionary.
        }
        
        let overallPercent = ProgressCalculator.overallPercentComplete(intentions: intentions, totalsByIntentionId: totalsByIntentionId) // Compute average completion ratio across eligible active intentions.
        let percentInt = max(0, min(100, Int((overallPercent * 100).rounded()))) // Convert 0...1 ratio into clamped whole-number percentage for user-facing text.
        let hasCheckedInToday = !checkIns.isEmpty // Condition A: whether at least one check-in exists today.
        let isBelowFiftyPercent = overallPercent < 0.5 // Condition B: progress threshold trigger requested by product requirement.
        let shouldNotify = (!hasCheckedInToday) || isBelowFiftyPercent // Notify when either condition is true (no check-in OR below 50%).
        return (shouldNotify, percentInt) // Return computed decision + text value for notification body.
    }
    
    /// Returns today's configured reminder date only when it is still upcoming.
    private func scheduledReminderDateIfStillUpcoming(reference: Date) -> Date? {
        let calendar = Calendar.current // Use local calendar so configured reminder time aligns with user's timezone.
        var reminderComponents = calendar.dateComponents([.year, .month, .day], from: reference) // Start with today's date components.
        let preferredTime = ReminderPreferences.reminderTimeComponents // Load persisted user-selected reminder hour/minute.
        reminderComponents.hour = preferredTime.hour ?? 18 // Apply configured hour with 6 PM fallback for safety.
        reminderComponents.minute = preferredTime.minute ?? 0 // Apply configured minute with :00 fallback for safety.
        reminderComponents.second = 0 // Set trigger second at :00 for deterministic schedule time.
        
        guard let todayReminderTime = calendar.date(from: reminderComponents) else { return nil } // Build today's reminder date safely from configured components.
        guard reference < todayReminderTime else { return nil } // Only keep today's reminder when current time is still before configured reminder time.
        return todayReminderTime // Return valid upcoming trigger date for today's reminder.
    }
}
