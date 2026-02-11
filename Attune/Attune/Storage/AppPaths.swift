//
//  AppPaths.swift
//  Attune
//
//  Provides centralized path management for app storage directories.
//

import Foundation

/// Centralized management of application storage paths.
/// All data is stored under Documents/Attune/ for easy inspection.
struct AppPaths {
    
    // MARK: - Base Directories
    
    /// Base directory: Documents/Attune/
    static var baseDir: URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDir.appendingPathComponent("Attune")
    }
    
    /// Sessions directory: Documents/Attune/Sessions/
    /// Contains individual session JSON files
    static var sessionsDir: URL {
        baseDir.appendingPathComponent("Sessions")
    }
    
    /// Extractions directory: Documents/Attune/Extractions/
    /// Contains individual extraction JSON files (one per session)
    static var extractionsDir: URL {
        baseDir.appendingPathComponent("Extractions")
    }
    
    /// Topics directory: Documents/Attune/Topics/
    /// Contains the aggregated Topics.json file
    static var topicsDir: URL {
        baseDir.appendingPathComponent("Topics")
    }
    
    /// Corrections file: Documents/Attune/Corrections.json
    /// Contains user corrections to extracted items (root level, parallel to Sessions/ and Topics/)
    static var correctionsFileURL: URL {
        baseDir.appendingPathComponent("Corrections.json")
    }
    
    /// Audio directory for a specific session: Documents/Attune/Audio/<sessionId>/
    /// Each session has its own audio subdirectory
    static func audioDir(sessionId: String) -> URL {
        baseDir.appendingPathComponent("Audio").appendingPathComponent(sessionId)
    }
    
    // MARK: - Helpers
    
    /// Returns the file URL for a session's JSON file
    /// Format: Documents/Attune/Sessions/<sessionId>.json
    static func sessionFileURL(sessionId: String) -> URL {
        sessionsDir.appendingPathComponent("\(sessionId).json")
    }
    
    /// Returns the file URL for a session's extractions JSON file
    /// Format: Documents/Attune/Extractions/<sessionId>.json
    static func extractionFileURL(sessionId: String) -> URL {
        extractionsDir.appendingPathComponent("\(sessionId).json")
    }
    
    /// Returns the file URL for the Topics.json file
    /// Format: Documents/Attune/Topics/Topics.json
    static var topicsFileURL: URL {
        topicsDir.appendingPathComponent("Topics.json")
    }
    
    /// Returns the file URL for a segment's audio file
    /// Format: Documents/Attune/Audio/<sessionId>/<audioFileName>
    static func audioFileURL(sessionId: String, audioFileName: String) -> URL {
        audioDir(sessionId: sessionId).appendingPathComponent(audioFileName)
    }
    
    // MARK: - Directory Creation
    
    /// Ensures all necessary directories exist, creating them if needed
    static func ensureDirectoriesExist() throws {
        let fileManager = FileManager.default
        
        // Create base directory
        try fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        
        // Create sessions directory
        try fileManager.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        
        // Create extractions directory
        try fileManager.createDirectory(at: extractionsDir, withIntermediateDirectories: true)
        
        // Create topics directory
        try fileManager.createDirectory(at: topicsDir, withIntermediateDirectories: true)
        
        // Audio directories are created per-session as needed
    }
    
    /// Ensures the audio directory exists for a specific session
    static func ensureAudioDirectory(sessionId: String) throws {
        let audioDirURL = audioDir(sessionId: sessionId)
        try FileManager.default.createDirectory(at: audioDirURL, withIntermediateDirectories: true)
    }
    
    // MARK: - File Existence Checks
    
    /// Checks if an audio file exists for a specific segment
    /// Returns false if audioFileName is empty or if the file doesn't exist
    static func audioFileExists(sessionId: String, audioFileName: String) -> Bool {
        guard !audioFileName.isEmpty else { return false }
        let fileURL = audioFileURL(sessionId: sessionId, audioFileName: audioFileName)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}
