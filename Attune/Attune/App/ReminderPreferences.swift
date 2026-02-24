//
//  ReminderPreferences.swift
//  Attune
//
//  Stores user-configurable reminder time for daily notifications.
//

import Foundation // Needed for Date and DateComponents types used by reminder time preferences.

/// Centralized storage for reminder settings so UI and services stay in sync.
enum ReminderPreferences {
    
    /// UserDefaults key for reminder hour in 24-hour format (0...23).
    private static let reminderHourKey = "attune.reminder.hour" // Stable key for persisted reminder hour.
    
    /// UserDefaults key for reminder minute (0...59).
    private static let reminderMinuteKey = "attune.reminder.minute" // Stable key for persisted reminder minute.
    
    /// UserDefaults key controlling whether the in-app daily reminder is enabled.
    private static let reminderEnabledKey = "attune.reminder.enabled" // Stable key for persisted on/off state of daily reminder feature.
    
    /// Default reminder hour (6 PM) used when user has not selected a custom time.
    private static let defaultHour = 18 // Product default reminder time hour.
    
    /// Default reminder minute (:00) used when user has not selected a custom time.
    private static let defaultMinute = 0 // Product default reminder time minute.
    
    /// Default in-app reminder toggle value when user has not set a preference.
    private static let defaultIsEnabled = true // Keep reminder enabled by default so feature works immediately for new users.
    
    /// Current in-app reminder enabled preference.
    static var isReminderEnabled: Bool {
        get {
            let defaults = UserDefaults.standard // Read persisted reminder enabled flag from standard defaults.
            if defaults.object(forKey: reminderEnabledKey) == nil { return defaultIsEnabled } // Use default true when user has never changed the toggle.
            return defaults.bool(forKey: reminderEnabledKey) // Return stored enabled flag when it exists.
        }
        set {
            let defaults = UserDefaults.standard // Persist new enabled flag in standard defaults.
            defaults.set(newValue, forKey: reminderEnabledKey) // Save on/off preference so toggle state survives app restarts.
        }
    }
    
    /// Current reminder time as hour/minute components.
    static var reminderTimeComponents: DateComponents {
        get {
            let defaults = UserDefaults.standard // Read persisted reminder values from standard defaults.
            let hour = defaults.object(forKey: reminderHourKey) as? Int ?? defaultHour // Use stored hour or default when missing.
            let minute = defaults.object(forKey: reminderMinuteKey) as? Int ?? defaultMinute // Use stored minute or default when missing.
            return DateComponents(hour: hour, minute: minute) // Return components consumed by scheduling logic.
        }
        set {
            let hour = max(0, min(23, newValue.hour ?? defaultHour)) // Clamp hour into valid range to protect against invalid writes.
            let minute = max(0, min(59, newValue.minute ?? defaultMinute)) // Clamp minute into valid range to protect against invalid writes.
            let defaults = UserDefaults.standard // Persist validated values in standard defaults.
            defaults.set(hour, forKey: reminderHourKey) // Save reminder hour so it survives app restarts.
            defaults.set(minute, forKey: reminderMinuteKey) // Save reminder minute so it survives app restarts.
        }
    }
    
    /// Current reminder time as Date on today's calendar day for DatePicker binding convenience.
    static var reminderTimeDate: Date {
        get {
            let calendar = Calendar.current // Use local calendar/timezone to construct today's time.
            let now = Date() // Anchor reminder time to current day for UI display.
            var components = calendar.dateComponents([.year, .month, .day], from: now) // Start with today's date.
            let time = reminderTimeComponents // Load persisted reminder hour/minute preferences.
            components.hour = time.hour ?? defaultHour // Apply persisted/default hour.
            components.minute = time.minute ?? defaultMinute // Apply persisted/default minute.
            components.second = 0 // Normalize seconds for consistent display and scheduling.
            return calendar.date(from: components) ?? now // Return best-effort date; fallback prevents nil in UI.
        }
        set {
            let calendar = Calendar.current // Use local calendar/timezone when extracting picked time.
            let components = calendar.dateComponents([.hour, .minute], from: newValue) // Extract hour/minute chosen by user.
            reminderTimeComponents = components // Persist extracted reminder components.
        }
    }
}
