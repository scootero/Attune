//
//  TranscriptionWorker.swift
//  Pondera
//
//  Worker that transcribes a closed audio file using SpeechAnalyzer + SpeechTranscriber.
//  Exposes a single async method to transcribe a file URL and return the transcript text.
//

import Foundation
import Speech

struct TranscriptionResult {
    let transcriptText: String
    let trustedTranscriptText: String
    let spans: [TranscriptSpan]
    let averageConfidence: Double?
    let quality: String
    let qualityReasons: [String]

    var allowsExtraction: Bool {
        quality != "lowTrust" && quality != "silent" && !trustedTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Worker that handles the actual transcription of audio files.
/// Uses Apple's SpeechAnalyzer and SpeechTranscriber APIs for closed file transcription.
class TranscriptionWorker {
    
    /// Transcribes an audio file and returns the transcript text.
    /// - Parameter url: The file URL of the closed audio segment to transcribe.
    /// - Returns: A string containing the transcribed text.
    /// - Throws: An error if transcription fails or if permissions are denied.
    func transcribeFile(url: URL, sessionId: String, segmentIndex: Int) async throws -> String {
        let result = try await transcribeFileWithQuality(url: url, sessionId: sessionId, segmentIndex: segmentIndex)
        return result.transcriptText
    }

    /// Transcribes an audio file and returns recognizer confidence metadata.
    /// The original transcript remains available, but downstream extraction should
    /// use trustedTranscriptText and respect allowsExtraction.
    func transcribeFileWithQuality(url: URL, sessionId: String, segmentIndex: Int) async throws -> TranscriptionResult {
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
            let recognitionResult: SFSpeechRecognitionResult = try await withCheckedThrowingContinuation { continuation in
                var didResume = false
                recognizer.recognitionTask(with: request) { result, error in
                    guard !didResume else { return }

                    // Check for errors first
                    if let error = error {
                        didResume = true
                        continuation.resume(throwing: TranscriptionError.recognitionFailed(error.localizedDescription))
                        return
                    }
                    
                    // Check if this is the final result
                    if let result = result, result.isFinal {
                        didResume = true
                        continuation.resume(returning: result)
                    }
                }
            }

            let result = makeResult(from: recognitionResult)
            
            // Log successful transcription with preview
            let preview = AppLogger.previewText(result.transcriptText, wordLimit: 8)
            let confidenceText = result.averageConfidence.map { String(format: "%.2f", $0) } ?? "nil"
            AppLogger.log(
                AppLogger.TSCR,
                "Transcription done session=\(AppLogger.shortId(sessionId)) seg=\(segmentIndex) quality=\(result.quality) confidence=\(confidenceText) trustedChars=\(result.trustedTranscriptText.count) words=\"\(preview)\""
            )
            
            return result
            
        } catch {
            // Log transcription failure
            AppLogger.log(AppLogger.ERR, "Transcription failed session=\(AppLogger.shortId(sessionId)) seg=\(segmentIndex) error=\"\(error.localizedDescription)\"")
            throw error
        }
    }

    private func makeResult(from recognitionResult: SFSpeechRecognitionResult) -> TranscriptionResult {
        let transcript = recognitionResult.bestTranscription.formattedString
        let sourceSegments = recognitionResult.bestTranscription.segments

        guard !sourceSegments.isEmpty else {
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            let quality = trimmed.isEmpty ? "silent" : "mixed"
            return TranscriptionResult(
                transcriptText: transcript,
                trustedTranscriptText: trimmed,
                spans: [],
                averageConfidence: nil,
                quality: quality,
                qualityReasons: trimmed.isEmpty ? ["no_transcript_text"] : ["no_confidence_metadata"]
            )
        }

        let spans = sourceSegments.map { segment in
            let confidence = max(0, min(1, Double(segment.confidence)))
            return TranscriptSpan(
                text: segment.substring,
                startTime: segment.timestamp,
                duration: segment.duration,
                confidence: confidence,
                trust: Self.spanTrust(confidence: confidence)
            )
        }

        let averageConfidence = spans.map(\.confidence).reduce(0, +) / Double(spans.count)
        let trustedSpans = spans.filter { $0.trust == "trusted" }
        let trustedText = trustedSpans.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let totalWordCount = max(1, spans.count)
        let trustedRatio = Double(trustedSpans.count) / Double(totalWordCount)

        var reasons: [String] = []
        if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons.append("no_transcript_text")
        }
        if averageConfidence < 0.35 {
            reasons.append("low_average_confidence")
        } else if averageConfidence < 0.55 {
            reasons.append("medium_average_confidence")
        }
        if trustedRatio < 0.35 {
            reasons.append("low_trusted_word_ratio")
        } else if trustedRatio < 0.70 {
            reasons.append("mixed_trusted_word_ratio")
        }
        if trustedSpans.count < 4 && !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons.append("too_few_trusted_words")
        }
        if Self.hasCoherenceWarning(transcript) {
            reasons.append("possible_word_salad")
        }

        var quality: String
        if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            quality = "silent"
        } else if averageConfidence < 0.35 || trustedRatio < 0.35 || trustedSpans.count < 4 {
            quality = "lowTrust"
        } else if averageConfidence < 0.55 || trustedRatio < 0.70 {
            quality = "mixed"
        } else {
            quality = "trusted"
        }
        if reasons.contains("possible_word_salad"), quality == "mixed" {
            quality = "lowTrust"
        }

        return TranscriptionResult(
            transcriptText: transcript,
            trustedTranscriptText: trustedText,
            spans: spans,
            averageConfidence: averageConfidence,
            quality: quality,
            qualityReasons: reasons
        )
    }

    private static func spanTrust(confidence: Double) -> String {
        if confidence >= 0.55 { return "trusted" }
        if confidence >= 0.30 { return "uncertain" }
        return "discarded"
    }

    private static func hasCoherenceWarning(_ text: String) -> Bool {
        let words = text.split { !$0.isLetter && !$0.isNumber }
        guard words.count >= 45 else { return false }

        let sentenceEndCount = text.reduce(0) { count, character in
            ".!?".contains(character) ? count + 1 : count
        }
        let longRunWithoutPunctuation = words.count >= 90 && sentenceEndCount <= 1

        let shortWords = words.filter { $0.count <= 3 }.count
        let shortWordRatio = Double(shortWords) / Double(words.count)
        let lowGlueRatio = shortWordRatio < 0.30

        return longRunWithoutPunctuation && lowGlueRatio
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
