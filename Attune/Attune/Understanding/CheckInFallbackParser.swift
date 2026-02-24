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
        
        // Workout: broadened keywords for exercise variants
        let workoutKeywords = ["workout", "worked out", "gym", "exercise", "trained", "training", "run", "running", "jog", "jogging", "lift", "lifting", "weights", "weightlifting", "strength", "cardio", "hiit", "treadmill", "squat", "deadlift", "bench"] // List of substrings that imply workout-related activity
        let hasWorkout = workoutKeywords.contains(where: { lower.contains($0) }) // Detect workout mentions in transcript
        let matchedKeyword = workoutKeywords.first(where: { lower.contains($0) }) // Capture first matching workout keyword for debug logs
        if hasWorkout { // Only proceed when workout language is present
            let intention = intentions.first { intention in // Find a matching workout intention
                let titleLower = intention.title.lowercased() // Lowercase title for substring checks
                let aliasesLower = intention.aliases.map { $0.lowercased() } // Lowercase aliases for substring checks
                let titleHit = workoutKeywords.contains(where: { titleLower.contains($0) }) // Match title against workout keywords
                let aliasHit = aliasesLower.contains(where: { alias in workoutKeywords.contains(where: { alias.contains($0) }) }) // Match any alias against workout keywords
                return titleHit || aliasHit // Accept intention if title or alias signals workout
            } // End intention search

            if let intention = intention { // Proceed only when a workout intention is found
                let unitLower = intention.unit.lowercased() // Normalize unit for comparisons
                var amountToUse: Double? // Holder for chosen amount
                var minutesConsumed = false // Track whether we consumed a parsed minutes value

                if minutesIdx < minutesAmounts.count { // Use parsed minutes when available
                    amountToUse = minutesAmounts[minutesIdx] // Set amount from parsed minutes
                    minutesIdx += 1 // Advance minutes index to avoid reusing same match
                    minutesConsumed = true // Record that we used a parsed value
#if DEBUG
                    AppLogger.log(AppLogger.AI, "checkin_fallback_debug workout_keyword=\(matchedKeyword ?? "unknown") amount_source=extracted_minutes amount=\(amountToUse ?? 0)") // Debug: log parsed minutes usage
#endif
                } else if unitLower.contains("min") { // Fallback for minute-based intentions without explicit numbers
                    let fallbackAmount = intention.targetValue > 0 ? intention.targetValue : 30 // Prefer targetValue; else default to 30 minutes
                    amountToUse = fallbackAmount // Set amount from fallback
#if DEBUG
                    AppLogger.log(AppLogger.AI, "checkin_fallback_debug workout_keyword=\(matchedKeyword ?? "unknown") amount_source=\(intention.targetValue > 0 ? "target_default" : "hard_default_30") amount=\(amountToUse ?? 0)") // Debug: log which minute fallback amount was chosen
#endif
                } else if unitLower.contains("session") || unitLower == "times" || unitLower.contains("workout") { // Handle session-like units
                    amountToUse = 1 // Default one session when no numeric amount is stated
#if DEBUG
                    AppLogger.log(AppLogger.AI, "checkin_fallback_debug workout_keyword=\(matchedKeyword ?? "unknown") amount_source=session_default_1 amount=1") // Debug: log session default fallback
#endif
                } // Other units are skipped to preserve current behavior

                if let amount = amountToUse { // Only append update when we have an amount
                    updates.append(CheckInUpdate( // Build fallback update payload
                        intentionId: intention.id, // Apply to matched workout intention
                        updateType: "INCREMENT", // Fallback always increments
                        amount: amount, // Use parsed or fallback amount
                        unit: unitLower.contains("min") ? "minutes" : intention.unit, // Use minutes for minute-based, otherwise original unit
                        confidence: Self.fallbackConfidence, // Use existing fallback confidence
                        evidence: nil // No evidence snippet in fallback
                    )) // Append constructed update
                } else { // No valid amount derived
                    _ = minutesConsumed // No-op to satisfy compiler for unused flag in this branch
#if DEBUG
                    AppLogger.log(AppLogger.AI, "checkin_fallback_debug workout_keyword=\(matchedKeyword ?? "unknown") amount_source=none reason=unsupported_unit") // Debug: log when no amount could be derived
#endif
                }
            }
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
