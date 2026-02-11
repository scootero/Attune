//
//  HomeRecordView.swift
//  Attune
//
//  Home screen with Record/Stop button, elapsed duration, and segment number.
//  Wired to RecorderService for real audio recording.
//

import SwiftUI

struct HomeRecordView: View {
    /// Shared recorder service
    @StateObject private var recorder = RecorderService.shared
    
    /// Shared transcription queue (for status display)
    @StateObject private var transcriptionQueue = TranscriptionQueue.shared
    
    /// Track if we're in processing state (for UI display)
    @State private var isProcessing = false
    
    /// Timer to check processing status
    @State private var processingCheckTimer: Timer?
    
    var body: some View {
        VStack(spacing: 40) {
            // Title at top
            Text("Attune")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, 40)
            
            Spacer()
            
            // Centered record button
            Button(action: toggleRecording) {
                ZStack {
                    // Background circle
                    Circle()
                        .fill(isProcessing ? Color.gray : Color.red)
                        .frame(width: 120, height: 120)
                    
                    // Icon: record circle when idle, square stop when recording, spinner when processing
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    } else if recorder.isRecording {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white)
                            .frame(width: 40, height: 40)
                    } else {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 60, height: 60)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isProcessing) // Disable button while processing
            
            Spacer()
            
            // Duration and segment display
            VStack(spacing: 16) {
                if isProcessing {
                    Text("Processing...")
                        .font(.title2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Duration: \(formattedDuration)")
                        .font(.title2)
                        .monospacedDigit()
                }
                
                Text("Segment: \(recorder.currentSegmentIndex)")
                    .font(.title3)
                    .foregroundColor(.secondary)
                
                // Transcription queue status (optional display)
                if transcriptionQueue.isRunning || transcriptionQueue.pendingCount > 0 {
                    HStack(spacing: 8) {
                        if transcriptionQueue.isRunning {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text("Queue: \(transcriptionQueue.pendingCount)")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.bottom, 40)
        }
        .onAppear {
            // Start checking for processing sessions on appear
            startProcessingCheck()
        }
        .onDisappear {
            // Stop timer when view disappears
            processingCheckTimer?.invalidate()
            processingCheckTimer = nil
        }
    }
    
    // Format elapsed seconds as mm:ss
    private var formattedDuration: String {
        let minutes = recorder.elapsedSec / 60
        let seconds = recorder.elapsedSec % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // Toggle recording state through RecorderService
    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stopRecording()
        } else {
            recorder.startRecording()
        }
    }
    
    /// Checks if there are any sessions in "processing" status and updates UI accordingly
    private func checkProcessingStatus() {
        let sessions = SessionStore.shared.loadAllSessions()
        let hasProcessingSessions = sessions.contains { $0.status == "processing" }
        isProcessing = hasProcessingSessions
    }
    
    /// Starts a timer to periodically check for processing sessions
    private func startProcessingCheck() {
        // Initial check
        checkProcessingStatus()
        
        // Check every second for processing sessions
        processingCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            checkProcessingStatus()
        }
    }
}

#Preview {
    HomeRecordView()
}
