//
//  AppLogger.swift
//  Attune
//
//  Structured debug logging for recording, transcription, and persistence flows.
//  Provides clear, filterable console output for tracing Sessions and Segments.
//  Logs are persisted to file and kept in memory for viewing in Settings.
//

import Foundation

/// Centralized logger for debug console output and persistent storage.
/// Provides structured logging with prefixes, timestamps, and key-value pairs.
struct AppLogger {
    
    // MARK: - Log Prefixes
    
    /// Recording lifecycle events
    static let REC = "<REC>"
    
    /// Segment lifecycle events
    static let SEG = "<SEG>"
    
    /// File I/O operations
    static let FILE = "<FILE>"
    
    /// Transcription queue operations
    static let QUE = "<QUE>"
    
    /// Transcription worker operations
    static let TSCR = "<TSCR>"
    
    /// Persistence operations
    static let STORE = "<STORE>"
    
    /// Error events
    static let ERR = "<ERR>"
    
    /// AI/LLM operations
    static let AI = "<AI>"
    
    // MARK: - Log Storage
    
    /// In-memory buffer of recent log entries (last 1000 entries)
    private static var logBuffer: [String] = []
    
    /// Maximum number of log entries to keep in memory
    private static let maxBufferSize = 1000
    
    /// Maximum log file size before rotation (5MB)
    private static let maxLogFileSize: UInt64 = 5 * 1024 * 1024
    
    /// Serial queue for thread-safe log operations
    private static let logQueue = DispatchQueue(label: "com.attune.logger", qos: .utility)
    
    /// Logs directory: Documents/Attune/Logs/
    private static var logsDir: URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDir.appendingPathComponent("Attune").appendingPathComponent("Logs")
    }
    
    /// Current log file URL: Documents/Attune/Logs/app.log
    private static var logFileURL: URL {
        logsDir.appendingPathComponent("app.log")
    }
    
    /// Archived log file URL: Documents/Attune/Logs/app.log.old
    private static var archivedLogFileURL: URL {
        logsDir.appendingPathComponent("app.log.old")
    }
    
    // MARK: - ISO8601 Formatter
    
    /// ISO8601 date formatter for timestamp generation
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()
    
    // MARK: - Initialization
    
    /// Ensures the logs directory exists
    private static func ensureLogsDirectoryExists() {
        logQueue.async {
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: logsDir.path) {
                try? fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
            }
        }
    }
    
    // MARK: - Public API
    
    /// Logs a message with a prefix and timestamp.
    /// Format: <PREFIX> ISO8601_TIMESTAMP message
    /// Writes to console, in-memory buffer, and persistent file.
    /// - Parameters:
    ///   - prefix: The log prefix (e.g., "<REC>", "<SEG>")
    ///   - message: The log message with key=value pairs
    static func log(_ prefix: String, _ message: String) {
        let timestamp = iso8601Formatter.string(from: Date())
        let logEntry = "\(prefix) \(timestamp) \(message)"
        
        // Print to console (for Xcode debugging)
        print(logEntry)
        
        // Store in buffer and file asynchronously
        logQueue.async {
            // Add to in-memory buffer
            logBuffer.append(logEntry)
            
            // Trim buffer if it exceeds max size
            if logBuffer.count > maxBufferSize {
                logBuffer.removeFirst(logBuffer.count - maxBufferSize)
            }
            
            // Write to file
            writeToFile(logEntry)
        }
    }
    
    /// Retrieves all logs from both in-memory buffer and file.
    /// Returns logs in chronological order (oldest first).
    /// - Returns: All log entries as a single string, separated by newlines
    static func getAllLogs() -> String {
        var allLogs: String = ""
        
        logQueue.sync {
            // Read from file first (contains older logs)
            if let fileContents = try? String(contentsOf: logFileURL, encoding: .utf8) {
                allLogs = fileContents
            }
            
            // If buffer has logs not yet in file, append them
            // (In practice, file writes are fast, but this ensures completeness)
            if !logBuffer.isEmpty {
                let bufferString = logBuffer.joined(separator: "\n")
                if !allLogs.isEmpty && !allLogs.hasSuffix("\n") {
                    allLogs += "\n"
                }
                allLogs += bufferString
            }
        }
        
        return allLogs
    }
    
    /// Returns the URL of the log file for export.
    /// - Returns: URL pointing to the current log file
    static func getLogFileURL() -> URL {
        return logFileURL
    }
    
    // MARK: - Private Helpers
    
    /// Writes a log entry to the persistent log file.
    /// Handles file creation, rotation, and appending.
    /// Must be called from logQueue.
    private static func writeToFile(_ logEntry: String) {
        ensureLogsDirectoryExists()
        
        let fileManager = FileManager.default
        let logData = (logEntry + "\n").data(using: .utf8)!
        
        // Check if file exists
        if fileManager.fileExists(atPath: logFileURL.path) {
            // Check file size and rotate if needed
            if let attributes = try? fileManager.attributesOfItem(atPath: logFileURL.path),
               let fileSize = attributes[.size] as? UInt64,
               fileSize > maxLogFileSize {
                rotateLogFile()
            }
            
            // Append to existing file
            if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(logData)
                try? fileHandle.close()
            }
        } else {
            // Create new file
            try? logData.write(to: logFileURL, options: .atomic)
        }
    }
    
    /// Rotates the log file by moving current log to .old and starting fresh.
    /// Must be called from logQueue.
    private static func rotateLogFile() {
        let fileManager = FileManager.default
        
        // Remove old archived log if it exists
        if fileManager.fileExists(atPath: archivedLogFileURL.path) {
            try? fileManager.removeItem(at: archivedLogFileURL)
        }
        
        // Move current log to archive
        try? fileManager.moveItem(at: logFileURL, to: archivedLogFileURL)
    }
    
    // MARK: - Helper Methods
    
    /// Generates a short ID from a UUID string (first 6 characters).
    /// - Parameter uuid: The full UUID string
    /// - Returns: The first 6 characters of the UUID
    static func shortId(_ uuid: String) -> String {
        return String(uuid.prefix(6))
    }
    
    /// Generates a preview of text by truncating to a word limit.
    /// - Parameters:
    ///   - text: The full text to preview
    ///   - wordLimit: Maximum number of words to include (default: 8)
    /// - Returns: Preview text with "…" suffix if truncated
    static func previewText(_ text: String, wordLimit: Int = 8) -> String {
        let words = text.split(separator: " ")
        
        if words.count <= wordLimit {
            return text
        }
        
        let preview = words.prefix(wordLimit).joined(separator: " ")
        return preview + "…"
    }
}
