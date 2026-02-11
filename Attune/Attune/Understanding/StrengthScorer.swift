//
//  StrengthScorer.swift
//  Attune
//
//  Phase 3: Strength scoring (local, LOW baseline).
//  Single occurrences should feel weak. Importance emerges from repetition + decay (later phase).
//  Strength is per-item only in v1.
//
//  Design intent: Simple heuristic rubric based on linguistic patterns.
//  Rule: Do NOT incorporate occurrence count. Do NOT compute topic-level strength.
//

import Foundation

/// Service for computing strength scores for individual extracted items.
/// Strength indicates the linguistic intensity/commitment level of the item,
/// NOT its importance or frequency (which will be handled by repetition + decay in later phases).
struct StrengthScorer {
    
    // MARK: - Public API
    
    /// Computes a strength score for an extracted item based on its text.
    /// Analyzes title + sourceQuote for linguistic intensity patterns.
    ///
    /// Heuristic rubric:
    /// - Strong commitment ("must", "need to", "have to", "will") → ~0.60
    /// - Moderate intent ("want to", "plan to", "going to") → ~0.50
    /// - Weak/uncertain ("maybe", "might", "consider") → ~0.25
    /// - Mood-related → ~0.35
    /// - Default → ~0.40
    ///
    /// Output is clamped to [0.20 – 0.65] range.
    ///
    /// - Parameters:
    ///   - title: The item's title
    ///   - sourceQuote: The source quote from transcript
    /// - Returns: Strength score in range [0.20 – 0.65]
    static func computeStrength(title: String, sourceQuote: String) -> Double {
        // Combine title and quote for analysis
        let combinedText = "\(title) \(sourceQuote)".lowercased()
        
        // Apply heuristic rubric in priority order (check strongest signals first)
        
        // Strong commitment indicators → ~0.60
        if containsAny(combinedText, patterns: strongCommitmentPatterns) {
            return 0.60
        }
        
        // Moderate intent indicators → ~0.50
        if containsAny(combinedText, patterns: moderateIntentPatterns) {
            return 0.50
        }
        
        // Weak/uncertain indicators → ~0.25
        if containsAny(combinedText, patterns: weakUncertainPatterns) {
            return 0.25
        }
        
        // Mood-related indicators → ~0.35
        if containsAny(combinedText, patterns: moodPatterns) {
            return 0.35
        }
        
        // Default baseline → ~0.40
        return 0.40
    }
    
    // MARK: - Private Helpers
    
    /// Checks if text contains any of the provided patterns.
    /// - Parameters:
    ///   - text: The text to search (should be lowercased)
    ///   - patterns: Array of patterns to search for
    /// - Returns: true if any pattern is found
    private static func containsAny(_ text: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if text.contains(pattern) {
                return true
            }
        }
        return false
    }
    
    // MARK: - Pattern Lists
    
    /// Strong commitment patterns indicating high linguistic intensity.
    /// These suggest obligation or definite action.
    private static let strongCommitmentPatterns = [
        "must",
        "need to",
        "have to",
        "will"
    ]
    
    /// Moderate intent patterns indicating planning or desire.
    /// These suggest intention without strong commitment.
    private static let moderateIntentPatterns = [
        "want to",
        "plan to",
        "going to"
    ]
    
    /// Weak/uncertain patterns indicating low commitment.
    /// These suggest hesitation or consideration without clear intent.
    private static let weakUncertainPatterns = [
        "maybe",
        "might",
        "consider"
    ]
    
    /// Mood-related patterns (aligned with NormalizationRules mood tokens).
    /// Mood items are given a moderate-low score as they're observational.
    private static let moodPatterns = [
        "sad",
        "down",
        "depressed",
        "anxious",
        "stressed",
        "happy",
        "mood",
        "feeling",
        "feel"
    ]
}
