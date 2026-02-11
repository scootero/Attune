//
//  LogsView.swift
//  Attune
//
//  Logs viewer with real-time display and export functionality.
//  Shows all debug logs from the app for troubleshooting.
//

import SwiftUI
import Combine

struct LogsView: View {
    // State for logs content
    @State private var logsText: String = ""
    @State private var isAutoScrollEnabled: Bool = true
    
    // Timer for refreshing logs
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 0) {
            // Logs display
            ScrollViewReader { proxy in
                ScrollView {
                    Text(logsText.isEmpty ? "No logs yet..." : logsText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                        .id("logsContent")
                }
                .background(Color(UIColor.systemGroupedBackground))
                .onChange(of: logsText) { _ in
                    if isAutoScrollEnabled {
                        withAnimation {
                            proxy.scrollTo("logsContent", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Auto-scroll toggle
                Button(action: {
                    isAutoScrollEnabled.toggle()
                }) {
                    Image(systemName: isAutoScrollEnabled ? "arrow.down.circle.fill" : "arrow.down.circle")
                }
                
                // Export button
                ShareLink(
                    item: createExportFile(),
                    preview: SharePreview(
                        "Attune Logs",
                        image: Image(systemName: "doc.text")
                    )
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .onAppear {
            loadLogs()
        }
        .onReceive(timer) { _ in
            loadLogs()
        }
    }
    
    // MARK: - Helper Methods
    
    /// Loads logs from AppLogger
    private func loadLogs() {
        logsText = AppLogger.getAllLogs()
    }
    
    /// Creates a temporary file for export
    private func createExportFile() -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let fileName = "attune-logs-\(timestamp).txt"
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        // Write logs to temp file
        try? logsText.write(to: fileURL, atomically: true, encoding: .utf8)
        
        return fileURL
    }
}

#Preview {
    NavigationView {
        LogsView()
    }
}
