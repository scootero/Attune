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
    
    // MARK: - Intentions + Check-ins + Progress (Slice 2)
    
    /// Intentions directory: Documents/Attune/Intentions/
    /// One JSON file per intention: <intentionId>.json
    static var intentionsDir: URL {
        baseDir.appendingPathComponent("Intentions")
    }
    
    /// IntentionSets directory: Documents/Attune/IntentionSets/
    /// One JSON file per set: <intentionSetId>.json
    static var intentionSetsDir: URL {
        baseDir.appendingPathComponent("IntentionSets")
    }
    
    /// CheckIns directory: Documents/Attune/CheckIns/
    /// One JSON file per check-in: <checkInId>.json
    static var checkInsDir: URL {
        baseDir.appendingPathComponent("CheckIns")
    }
    
    /// ProgressEntries directory: Documents/Attune/ProgressEntries/
    /// One JSON file per progress entry: <entryId>.json
    static var progressEntriesDir: URL {
        baseDir.appendingPathComponent("ProgressEntries")
    }
    
    /// DailyMood directory: Documents/Attune/DailyMood/
    /// One JSON file per date: <dateKey>.json (e.g., 2026-02-11.json)
    static var dailyMoodDir: URL {
        baseDir.appendingPathComponent("DailyMood")
    }
    
    /// ProgressOverrides directory (Slice 7): Documents/Attune/ProgressOverrides/
    /// One JSON file per date: <dateKey>.json (array of overrides for that day)
    static var progressOverridesDir: URL {
        baseDir.appendingPathComponent("ProgressOverrides")
    }
    
    /// CheckInAudio directory (Slice 3): Documents/Attune/CheckInAudio/
    /// One audio file per check-in: <checkInId>.m4a
    static var checkInAudioDir: URL {
        baseDir.appendingPathComponent("CheckInAudio")
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
    
    /// Returns the file URL for an intention: Documents/Attune/Intentions/<id>.json
    static func intentionFileURL(intentionId: String) -> URL {
        intentionsDir.appendingPathComponent("\(intentionId).json")
    }
    
    /// Returns the file URL for an intention set: Documents/Attune/IntentionSets/<id>.json
    static func intentionSetFileURL(intentionSetId: String) -> URL {
        intentionSetsDir.appendingPathComponent("\(intentionSetId).json")
    }
    
    /// Returns the file URL for a check-in: Documents/Attune/CheckIns/<id>.json
    static func checkInFileURL(checkInId: String) -> URL {
        checkInsDir.appendingPathComponent("\(checkInId).json")
    }
    
    /// Returns the file URL for a progress entry: Documents/Attune/ProgressEntries/<id>.json
    static func progressEntryFileURL(entryId: String) -> URL {
        progressEntriesDir.appendingPathComponent("\(entryId).json")
    }
    
    /// Returns the file URL for daily mood: Documents/Attune/DailyMood/<dateKey>.json
    static func dailyMoodFileURL(dateKey: String) -> URL {
        dailyMoodDir.appendingPathComponent("\(dateKey).json")
    }
    
    /// Returns the file URL for day's overrides: Documents/Attune/ProgressOverrides/<dateKey>.json
    static func progressOverridesFileURL(dateKey: String) -> URL {
        progressOverridesDir.appendingPathComponent("\(dateKey).json")
    }
    
    /// Returns the file URL for check-in audio: Documents/Attune/CheckInAudio/<fileName>
    /// FileName is typically "<checkInId>.m4a"
    static func checkInAudioFileURL(fileName: String) -> URL {
        checkInAudioDir.appendingPathComponent(fileName)
    }
    
    /// Forms a YYYY-MM-DD date key from a Date using the current calendar (local time)
    static func dateKey(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
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
        
        // Slice 2: Intentions + Check-ins + Progress directories
        try fileManager.createDirectory(at: intentionsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: intentionSetsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: checkInsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: progressEntriesDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: dailyMoodDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: checkInAudioDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: progressOverridesDir, withIntermediateDirectories: true)
        
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
