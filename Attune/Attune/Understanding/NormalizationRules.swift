//
//  NormalizationRules.swift
//  Attune
//
//  Phase 2: Lightweight normalization rules (seed only).
//  Collapses obvious phrasing drift while preserving deterministic identity.
//  Applied in TopicKeyBuilder before slug construction.
//
//  Design intent: Data tuning, not architecture.
//  Rule: Implement the structure + listed examples only. Do NOT generalize or expand.
//

import Foundation

/// Seed normalization rules for collapsing common phrasing variations.
/// These are applied in order: phrase replacement → token normalization → time/frequency removal → stopword removal.
struct NormalizationRules {
    
    // MARK: - Phrase Map (seed examples — do not expand)
    
    /// Multi-word phrase replacements applied before tokenization.
    /// These collapse common phrasing variations into canonical forms.
    static let phraseMap: [(String, String)] = [
        // Fitness
        ("working out", "workout"),
        ("work out", "workout"),

        // Review
        ("go over", "review"),
        ("look at", "review"),
        ("check out", "review"),

        // Planning / intent
        ("figure out", "plan"),
        ("set up", "setup"),
        ("start to", "start"),
        ("going to", "will"),
        ("need to", "need"),
        
        // Travel / visiting (normalize to "visit")
        ("beach trip", "beach visit"),
        ("beach visit", "beach visit")
    ]
    
    // MARK: - Token Map (seed examples — do not expand)
    
    /// Single-token replacements applied after tokenization.
    /// These normalize synonyms and related concepts into canonical tokens.
    static let tokenMap: [String: String] = [
        // Fitness
        "exercise": "workout",
        "gym": "workout",
        "train": "workout",
        "training": "workout",
        "exercising": "workout",

        // Finance
        "finances": "finance",
        "money": "finance",
        "budget": "finance",

        // Review
        "review": "review",
        "check": "review",
        "verify": "review",

        // Mood (single-token only)
        "sad": "mood",
        "down": "mood",
        "depressed": "mood",
        "anxious": "mood",
        "stressed": "mood",
        "happy": "mood",
        
        // Travel / visiting (normalize to "visit")
        "trip": "visit",
        "visiting": "visit",
        "visited": "visit",
        "trips": "visit"
    ]
    
    // MARK: - Time & Frequency Tokens (explicit list)
    
    /// Time and frequency tokens to be removed during normalization.
    /// These describe WHEN or HOW OFTEN, not WHAT.
    /// CRITICAL: These are checked BEFORE length filtering to ensure consistent removal.
    static let timeFrequencyTokens: Set<String> = [
        // Absolute time
        "today", "tomorrow", "tonight", "yesterday",
        "morning", "afternoon", "evening", "night",
        "monday", "tuesday", "wednesday", "thursday", "friday",
        "saturday", "sunday",

        // Relative time
        "now", "later", "soon", "asap", "eventually",
        "this", "next", "last", "current", "past", "future",
        "week", "month", "year", "day", "time",
        "weeks", "months", "years", "days", "times",
        
        // Relative time phrases (single tokens after normalization)
        "ago", "before", "after", "since", "until", "during",

        // Frequency
        "daily", "weekly", "monthly", "yearly",
        "every", "each", "always", "often", "sometimes",
        "regularly", "occasionally", "frequently", "never", "rarely"
    ]
    
    // MARK: - Normalization Logic
    
    /// Applies phrase map replacements to text before tokenization.
    /// Iterates through phraseMap in order, replacing multi-word phrases.
    /// - Parameter text: Normalized (lowercased, no punctuation) text
    /// - Returns: Text with phrase replacements applied
    static func applyPhraseReplacements(_ text: String) -> String {
        var result = text
        for (phrase, replacement) in phraseMap {
            result = result.replacingOccurrences(of: phrase, with: replacement)
        }
        return result
    }
    
    /// Applies token map replacements to individual tokens.
    /// Normalizes synonyms and related concepts into canonical forms.
    /// - Parameter token: A single token (word)
    /// - Returns: The normalized token (or original if no mapping exists)
    static func applyTokenReplacement(_ token: String) -> String {
        return tokenMap[token] ?? token
    }
}
