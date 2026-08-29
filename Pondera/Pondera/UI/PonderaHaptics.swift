import UIKit

/// A small, consistent haptic vocabulary for user-visible actions.
/// Persistence code remains independent from haptics; callers trigger feedback
/// only after an operation has actually succeeded or failed.
@MainActor
enum PonderaHaptics {
    /// A quiet pulse as the branded launch handoff reveals the app.
    static func welcome() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.9)
    }

    /// Lightweight feedback for changing pages, tabs, or opening app chrome.
    static func selection() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.85)
    }

    static func action() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.55)
    }

    static func saved() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    static func reward() {
        let notification = UINotificationFeedbackGenerator()
        notification.prepare()
        notification.notificationOccurred(.success)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            let impact = UIImpactFeedbackGenerator(style: .rigid)
            impact.prepare()
            impact.impactOccurred(intensity: 0.85)
        }
    }

    static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
    }

    static func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
    }
}
