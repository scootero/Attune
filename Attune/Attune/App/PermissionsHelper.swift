//
//  PermissionsHelper.swift
//  Attune
//
//  Requests microphone and speech recognition permissions proactively when Home loads.
//  Shows system dialogs only when status is .undetermined/.notDetermined (first time).
//  If already authorized, these are no-ops; if denied, user must go to Settings.
//

import AVFoundation
import Speech

/// Requests microphone and speech recognition permissions when Home loads.
/// Only triggers system permission dialogs when the user hasn't been asked yet (.undetermined).
/// Call from HomeView.onAppear so users see prompts before their first recording attempt.
enum PermissionsHelper {

    /// Call when Home view appears. Requests both permissions only if not yet determined.
    static func requestRecordingPermissionsIfNeeded() {
        requestMicrophoneIfNeeded()
        requestSpeechRecognitionIfNeeded()
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
