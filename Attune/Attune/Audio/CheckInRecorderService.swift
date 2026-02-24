//
//  CheckInRecorderService.swift
//  Attune
//
//  Records a single check-in audio file (no segment rotation).
//  Separate pipeline from continuous recording — does NOT use TranscriptionQueue.
//  Saves to CheckInAudio/<checkInId>.m4a using same encoding as RecorderService.
//

import AVFoundation
import Combine
import Foundation

/// Records a single check-in audio clip. Uses same audio format as RecorderService.
/// Call startRecording(), then stopRecording() to get the audio file URL for transcription.
@MainActor
class CheckInRecorderService: NSObject, ObservableObject {
    
    // MARK: - Published State
    
    /// Whether recording is currently active
    @Published var isRecording = false
    
    /// Elapsed seconds since recording started (for UI timer display)
    @Published var elapsedSec = 0
    
    // MARK: - Singleton
    
    static let shared = CheckInRecorderService()
    
    // MARK: - Private State
    
    /// Current recorder instance
    private var recorder: AVAudioRecorder?
    
    /// Generated when startRecording() is called; used for filename and CheckIn id
    private var currentCheckInId: String?
    
    /// Timer that updates elapsedSec every second
    private var elapsedTimer: Timer?
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public API
    
    /// Starts recording a single check-in. Creates file at CheckInAudio/<checkInId>.m4a
    /// Uses same audio settings as RecorderService (AAC, 44.1kHz, mono).
    /// - Returns: The checkInId (used later for CheckIn model and filename)
    func startRecording() throws -> String {
        guard !isRecording else {
            throw CheckInRecorderError.alreadyRecording
        }
        
        // Generate id now; used for both filename and CheckIn.id
        let checkInId = UUID().uuidString
        let audioFileName = "\(checkInId).m4a"
        let audioURL = AppPaths.checkInAudioFileURL(fileName: audioFileName)
        
        // Ensure CheckInAudio directory exists (fast no-op if already exists)
        // This is called here as a safety check, but should already be created in HomeView.onAppear
        let checkInAudioDir = AppPaths.checkInAudioDir
        if !FileManager.default.fileExists(atPath: checkInAudioDir.path) {
            try FileManager.default.createDirectory(at: checkInAudioDir, withIntermediateDirectories: true)
        }
        
        // Reuse same audio session config as continuous recording
        try configureAudioSession()
        
        currentCheckInId = checkInId
        
        // Same audio settings as RecorderService (AAC, 44.1kHz, mono, high quality)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        let newRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
        newRecorder.delegate = self
        newRecorder.record()
        recorder = newRecorder
        
        isRecording = true
        elapsedSec = 0
        startElapsedTimer()
        
        AppLogger.log(AppLogger.REC, "Check-in recording started id=\(AppLogger.shortId(checkInId))")
        
        return checkInId
    }
    
    /// Stops recording and returns the checkInId and audio file URL for transcription.
    /// Caller is responsible for transcribing and saving the CheckIn.
    /// - Returns: Tuple of (checkInId, audioURL) or nil if no recording was active
    func stopRecording() -> (checkInId: String, audioURL: URL)? {
        guard isRecording, let checkInId = currentCheckInId else {
            return nil
        }
        
        stopElapsedTimer()
        recorder?.stop()
        recorder = nil
        
        isRecording = false
        currentCheckInId = nil
        
        let audioFileName = "\(checkInId).m4a"
        let audioURL = AppPaths.checkInAudioFileURL(fileName: audioFileName)
        
        AppLogger.log(AppLogger.REC, "Check-in recording stopped id=\(AppLogger.shortId(checkInId))")
        
        return (checkInId, audioURL)
    }
    
    // MARK: - Audio Session
    
    /// Same configuration as RecorderService: record category, Bluetooth mic support
    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .default, options: [.allowBluetooth])
        try audioSession.setActive(true)
    }
    
    // MARK: - Timer
    
    private func startElapsedTimer() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedSec += 1
            }
        }
        RunLoop.current.add(elapsedTimer!, forMode: .common)
    }
    
    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }
}

// MARK: - AVAudioRecorderDelegate

extension CheckInRecorderService: AVAudioRecorderDelegate {
    
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("[CheckInRecorderService] Recording finished unsuccessfully")
        }
    }
    
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("[CheckInRecorderService] Recorder encode error: \(error)")
        }
    }
}

// MARK: - Error Types

enum CheckInRecorderError: LocalizedError {
    case alreadyRecording
    
    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Already recording a check-in"
        }
    }
}
