//
//  TranscriptionWorker.swift
//  Attune
//
//  Worker that transcribes a closed audio file using SpeechAnalyzer + SpeechTranscriber.
//  Exposes a single async method to transcribe a file URL and return the transcript text.
//

import Foundation
import Speech

/// Worker that handles the actual transcription of audio files.
/// Uses Apple's SpeechAnalyzer and SpeechTranscriber APIs for closed file transcription.
class TranscriptionWorker {
    
    /// Transcribes an audio file and returns the transcript text.
    /// - Parameter url: The file URL of the closed audio segment to transcribe.
    /// - Returns: A string containing the transcribed text.
    /// - Throws: An error if transcription fails or if permissions are denied.
    func transcribeFile(url: URL, sessionId: String, segmentIndex: Int) async throws -> String {
        // Log transcription start
        let fileName = url.lastPathComponent
        AppLogger.log(AppLogger.TSCR, "Transcription started session=\(AppLogger.shortId(sessionId)) seg=\(segmentIndex) file=\(fileName)")
        
        // Request speech recognition authorization if needed
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        
        if authStatus == .notDetermined {
            // Request authorization and wait for result
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            
            if !granted {
                throw TranscriptionError.authorizationDenied
            }
        } else if authStatus != .authorized {
            throw TranscriptionError.authorizationDenied
        }
        
        // Create speech recognizer with locale
        guard let recognizer = SFSpeechRecognizer() else {
            throw TranscriptionError.recognizerUnavailable
        }
        
        if !recognizer.isAvailable {
            throw TranscriptionError.recognizerUnavailable
        }
        
        // Create transcription request for the file
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false // Only want final result
        request.requiresOnDeviceRecognition = false // Allow cloud if available
        
        // Perform recognition and collect results
        do {
            let result: String = try await withCheckedThrowingContinuation { continuation in
                recognizer.recognitionTask(with: request) { result, error in
                    // Check for errors first
                    if let error = error {
                        continuation.resume(throwing: TranscriptionError.recognitionFailed(error.localizedDescription))
                        return
                    }
                    
                    // Check if this is the final result
                    if let result = result, result.isFinal {
                        let transcript = result.bestTranscription.formattedString
                        continuation.resume(returning: transcript)
                    }
                }
            }
            
            // Log successful transcription with preview
            let preview = AppLogger.previewText(result, wordLimit: 8)
            AppLogger.log(AppLogger.TSCR, "Transcription done session=\(AppLogger.shortId(sessionId)) seg=\(segmentIndex) words=\"\(preview)\"")
            
            return result
            
        } catch {
            // Log transcription failure
            AppLogger.log(AppLogger.ERR, "Transcription failed session=\(AppLogger.shortId(sessionId)) seg=\(segmentIndex) error=\"\(error.localizedDescription)\"")
            throw error
        }
    }
}

// MARK: - Error Types

/// Errors that can occur during transcription
enum TranscriptionError: LocalizedError {
    case authorizationDenied
    case recognizerUnavailable
    case recognitionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Speech recognition authorization denied"
        case .recognizerUnavailable:
            return "Speech recognizer unavailable"
        case .recognitionFailed(let message):
            return "Recognition failed: \(message)"
        }
    }
}
