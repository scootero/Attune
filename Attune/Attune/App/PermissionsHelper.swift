//
//  PermissionsHelper.swift
//  Attune
//
//  Requests microphone, speech recognition, and notification permissions
//  at the moment the user starts the related feature (not on Home appear).
//

import AVFoundation
import Speech
import UserNotifications

/// Requests system permissions only when status is still undetermined.
/// Call from recording start (mic/speech) or when enabling reminders (notifications).
enum PermissionsHelper {

    /// Call right before the user starts recording a session or check-in.
    static func requestRecordingPermissionsIfNeeded() {
        requestMicrophoneIfNeeded()
        requestSpeechRecognitionIfNeeded()
    }
    
    /// Requests local notification permission if status is .notDetermined.
    /// Call when the user enables daily reminders in Settings.
    static func requestNotificationPermissionsIfNeeded() {
        let notificationCenter = UNUserNotificationCenter.current() // Use the shared notification center to read/request notification permissions.
        notificationCenter.getNotificationSettings { settings in // Read current notification authorization status before requesting anything.
            guard settings.authorizationStatus == .notDetermined else { return } // Only request once when iOS has not asked the user yet.
            notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in // Ask for visible alert, sound, and badge for reminder notifications.
                // Result is intentionally ignored here because reminder scheduling separately checks permission status.
            }
        }
    }

    /// Requests microphone permission if status is .undetermined.
    /// Uses AVAudioSession.recordPermission — when .undetermined, requestRecordPermission
    /// shows the system dialog. If already .granted or .denied, block runs immediately (no dialog).
    private static func requestMicrophoneIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        if session.recordPermission == .undetermined {
            session.requestRecordPermission { _ in
                // Result ignored here; caller (recorder) will handle denied when they try to record
            }
        }
    }

    /// Requests speech recognition permission if status is .notDetermined.
    /// SFSpeechRecognizer.requestAuthorization shows the system dialog only when .notDetermined.
    /// If already authorized or denied, callback fires immediately without a dialog.
    private static func requestSpeechRecognitionIfNeeded() {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { _ in
                // Result ignored here; TranscriptionWorker will handle denied when transcribing
            }
        }
    }
}
