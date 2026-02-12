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
    
    /// Today's session count (read-only query)
    @State private var todaySessionsCount: Int = 0
    /// Today's insights count (read-only query from ExtractedItem.createdAt)
    @State private var todayInsightsCount: Int = 0
    /// Presents sheet with Sessions list (Library → Sessions)
    @State private var showSessionsSheet = false
    /// Presents sheet with Insights list (Library → Insights)
    @State private var showInsightsSheet = false
    
    var body: some View {
        VStack(spacing: 40) {
            // Title at top (matches tab label "All Day")
            Text("All Day")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, 40)
            
            // Today counts card + deep links to Library (read-only)
            todayCountsCard
            
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
            startProcessingCheck()
            loadTodayCounts()
        }
        .onDisappear {
            processingCheckTimer?.invalidate()
            processingCheckTimer = nil
        }
        .sheet(isPresented: $showSessionsSheet, onDismiss: { loadTodayCounts() }) {
            NavigationView {
                SessionListView(sessions: SessionStore.shared.loadAllSessions())
                    .navigationTitle("Sessions")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showSessionsSheet = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showInsightsSheet, onDismiss: { loadTodayCounts() }) {
            NavigationView {
                InsightsListView()
                    .navigationTitle("Insights")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showInsightsSheet = false }
                        }
                    }
            }
        }
    }
    
    /// Small card: "Today: X sessions • Y insights" + View Sessions / View Insights buttons
    private var todayCountsCard: some View {
        VStack(spacing: 12) {
            Text("Today: \(todaySessionsCount) sessions • \(todayInsightsCount) insights")
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack(spacing: 16) {
                Button(action: { showSessionsSheet = true }) {
                    Text("View Sessions")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                Button(action: { showInsightsSheet = true }) {
                    Text("View Insights")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal, 24)
    }
    
    /// Loads today's session and insight counts (read-only; startOfDay..endOfDay local timezone)
    private func loadTodayCounts() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        // Sessions: filter by startedAt in today's range
        let sessions = SessionStore.shared.loadAllSessions()
        todaySessionsCount = sessions.filter { $0.startedAt >= startOfDay && $0.startedAt < endOfDay }.count
        // Insights: filter by ExtractedItem.createdAt (ISO8601 string); try both formats for compatibility
        let items = ExtractionStore.shared.loadAllExtractions()
        let fmtFrac = ISO8601DateFormatter()
        fmtFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fmtPlain = ISO8601DateFormatter()
        fmtPlain.formatOptions = [.withInternetDateTime]
        todayInsightsCount = items.filter { item in
            let d = fmtFrac.date(from: item.createdAt) ?? fmtPlain.date(from: item.createdAt)
            guard let date = d else { return false }
            return date >= startOfDay && date < endOfDay
        }.count
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
