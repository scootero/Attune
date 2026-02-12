//
//  CheckInFallbackParser.swift
//  Attune
//
//  Deterministic fallback when AI extraction fails or returns empty.
//  Parses common phrases (work on app, workout, read) and extracts minutes/pages
//  so progress still updates offline or on schema/network errors.
//

import Foundation

/// Parses transcript locally when AI extraction fails or returns empty updates.
/// Maps keywords to intentions by title and extracts (amount, unit) via regex.
struct CheckInFallbackParser {
    
    /// Regex for minutes: e.g. "30 min", "45 minutes", "1 minute"
    private static let minutesPattern = #"(\d+)\s*(?:min|mins|minute|minutes)\b"#
    
    /// Regex for pages: e.g. "10 pages", "3 page"
    private static let pagesPattern = #"(\d+)\s*(?:pages?|page)\b"#
    
    /// Confidence for fallback-extracted updates (lower than AI)
    private static let fallbackConfidence = 0.7
    
    /// Returns progress updates from transcript using regex/keyword matching.
    /// Only matches the 3 default intention types: Work on app, Workout, Read.
    /// - Parameters:
    ///   - transcript: The transcribed check-in text
    ///   - intentions: Current active intentions (we match by title)
    /// - Returns: Array of CheckInUpdate (all INCREMENT, confidence 0.7)
    static func parseFallbackUpdates(transcript: String, intentions: [Intention]) -> [CheckInUpdate] {
        let lower = transcript.lowercased()
        
        // 1. Extract (amount, unit) pairs from transcript (order preserved)
        var minutesAmounts: [Double] = []
        if let regex = try? NSRegularExpression(pattern: Self.minutesPattern, options: .caseInsensitive) {
            let range = NSRange(lower.startIndex..., in: lower)
            regex.enumerateMatches(in: lower, options: [], range: range) { match, _, _ in
                guard let m = match, m.numberOfRanges >= 2,
                      let r = Range(m.range(at: 1), in: lower),
                      let amount = Double(String(lower[r])) else { return }
                minutesAmounts.append(amount)
            }
        }
        
        var pagesAmounts: [Double] = []
        if let regex = try? NSRegularExpression(pattern: Self.pagesPattern, options: .caseInsensitive) {
            let range = NSRange(lower.startIndex..., in: lower)
            regex.enumerateMatches(in: lower, options: [], range: range) { match, _, _ in
                guard let m = match, m.numberOfRanges >= 2,
                      let r = Range(m.range(at: 1), in: lower),
                      let amount = Double(String(lower[r])) else { return }
                pagesAmounts.append(amount)
            }
        }
        
        // 2. Match transcript phrases to intentions; track next index per unit for assignment
        var minutesIdx = 0
        var pagesIdx = 0
        var updates: [CheckInUpdate] = []
        
        // App: "work on app", "worked on my app"
        if lower.contains("work") && (lower.contains("on") && lower.contains("app")) {
            if let intention = intentions.first(where: { $0.title.lowercased().contains("app") }),
               minutesIdx < minutesAmounts.count,
               intention.unit.lowercased().contains("min") {
                let amount = minutesAmounts[minutesIdx]
                minutesIdx += 1
                updates.append(CheckInUpdate(
                    intentionId: intention.id,
                    updateType: "INCREMENT",
                    amount: amount,
                    unit: "minutes",
                    confidence: Self.fallbackConfidence,
                    evidence: nil
                ))
            }
        }
        
        // Workout: "workout", "worked out", "gym"
        let hasWorkout = lower.contains("workout") || lower.contains("worked out") || lower.contains("gym")
        if hasWorkout,
           let intention = intentions.first(where: { $0.title.lowercased().contains("workout") || $0.title.lowercased().contains("gym") }),
           minutesIdx < minutesAmounts.count,
           intention.unit.lowercased().contains("min") {
            let amount = minutesAmounts[minutesIdx]
            minutesIdx += 1
            updates.append(CheckInUpdate(
                intentionId: intention.id,
                updateType: "INCREMENT",
                amount: amount,
                unit: "minutes",
                confidence: Self.fallbackConfidence,
                evidence: nil
            ))
        }
        
        // Read: "read"
        if lower.contains("read"),
           let intention = intentions.first(where: { $0.title.lowercased().contains("read") }),
           pagesIdx < pagesAmounts.count,
           intention.unit.lowercased().contains("page") {
            let amount = pagesAmounts[pagesIdx]
            pagesIdx += 1
            updates.append(CheckInUpdate(
                intentionId: intention.id,
                updateType: "INCREMENT",
                amount: amount,
                unit: "pages",
                confidence: Self.fallbackConfidence,
                evidence: nil
            ))
        }
        
        if !updates.isEmpty {
            AppLogger.log(AppLogger.AI, "checkin_fallback_used transcript_len=\(transcript.count) updates=\(updates.count)")
        }
        
        return updates
    }
}
