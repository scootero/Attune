//
//  TopicKeyBuilder.swift
//  Attune
//
//  Generates deterministic topic keys for reliable grouping across sessions.
//  Topic keys are format: "primaryCategory|conceptSlug"
//  Time/frequency qualifiers do NOT affect topic identity (e.g., "work out today" 
//  and "start working out daily" produce the same conceptSlug: "work_out").
//

import Foundation

/// Service for generating deterministic topic keys from extracted items.
/// Topic keys enable reliable grouping of similar concepts across sessions,
/// independent of AI fingerprints or phrasing variations.
struct TopicKeyBuilder {
    
    // MARK: - Category Priority
    
    /// Explicit priority list for selecting primary category.
    /// Categories are checked in order; first match is selected.
    /// This ensures stable topic keys regardless of category order in the array.
    static let categoryPriority: [String] = [
        "fitness_health",
        "health",
        "nutrition",
        "career",
        "work",
        "money_finance",
        "relationships_social",
        "family",
        "learning",
        "growth",
        "peace_wellbeing",
        "mental_health",
        "uncategorized"
    ]
    
    // MARK: - Public API
    
    /// Selects the primary category from a list of categories using priority order.
    /// This ensures deterministic category selection regardless of input order.
    /// - Parameter categories: Array of category strings
    /// - Returns: The primary category (highest priority, or alphabetically first, or "uncategorized")
    static func selectPrimaryCategory(from categories: [String]) -> String {
        // Check priority list in order
        for cat in categoryPriority {
            if categories.contains(cat) {
                return cat
            }
        }
        
        // Fallback: use first alphabetically sorted category or "uncategorized"
        return categories.sorted().first ?? "uncategorized"
    }
    
    /// Generates a deterministic topic key for an extracted item.
    /// Format: "conceptSlug" (category is NOT part of the key to prevent duplicates)
    /// Example: "beach_visit"
    ///
    /// The conceptSlug is derived from the item's title and sourceQuote by:
    /// 1. Combining title + sourceQuote
    /// 2. Normalizing (lowercase, strip punctuation, collapse whitespace)
    /// 3. Tokenizing and removing stopwords
    /// 4. Removing time/frequency qualifiers (today, daily, weekly, etc.)
    /// 5. Taking first 3-4 significant tokens
    ///
    /// NOTE: Category is deliberately excluded from the key to prevent duplicates when
    /// AI assigns different categories to the same concept (e.g., "Beach Visit" as both
    /// "relationships_social" and "personal_growth" should merge into ONE topic).
    ///
    /// - Parameters:
    ///   - item: The extracted item to generate a key for
    ///   - primaryCategory: The primary category for this item (unused, kept for API compatibility)
    /// - Returns: A deterministic topic key string (just the conceptSlug)
    static func makeTopicKey(item: ExtractedItem, primaryCategory: String) -> String {
        // Build concept slug from title and quote
        let conceptSlug = buildConceptSlug(title: item.title, quote: item.sourceQuote)
        
        // Return ONLY the conceptSlug (no category prefix)
        // This ensures topics merge even when AI assigns different categories
        return conceptSlug
    }
    
    // MARK: - Private Helpers
    
    /// Builds a normalized concept slug from title ONLY.
    /// CRITICAL FIX: Uses title only, NOT quote, to ensure stable topic keys.
    /// The quote contains variable context (e.g., "ran 4 miles" vs "went on a run")
    /// which causes the same topic to generate different keys.
    ///
    /// Applies Phase 2 normalization rules in order:
    /// 1. Phrase replacement (multi-word)
    /// 2. Token normalization (single-word synonyms)
    /// 3. Time/frequency token removal
    /// 4. Stopword removal
    ///
    /// Examples:
    /// - "work out today" → "workout"
    /// - "start working out daily" → "start_workout"
    /// - "meeting with boss tomorrow" → "meeting_boss"
    ///
    /// - Parameters:
    ///   - title: The item's title (ONLY source for topic key)
    ///   - quote: The source quote from transcript (UNUSED - kept for API compatibility)
    /// - Returns: A normalized concept slug (underscore-separated tokens)
    private static func buildConceptSlug(title: String, quote: String) -> String {
        // Use ONLY title for topic key generation (not quote)
        // This ensures "Beach Run" always produces the same key regardless of quote details
        let combinedText = title.lowercased()
        
        // Normalize: remove punctuation, collapse whitespace
        let normalized = normalizeText(combinedText)
        
        // Phase 2 SLICE P2.1: Apply phrase replacements before tokenization
        let withPhraseReplacements = NormalizationRules.applyPhraseReplacements(normalized)
        
        // Tokenize
        let tokens = withPhraseReplacements.split(separator: " ").map(String.init)
        
        // Phase 2 SLICE P2.1: Apply token normalization
        let normalizedTokens = tokens.map { NormalizationRules.applyTokenReplacement($0) }
        
        // Filter out stopwords, time/frequency tokens (Phase 2 rules used for time/frequency)
        let significantTokens = normalizedTokens.filter { token in
            isSignificantToken(token)
        }
        
        // Take first 3-4 significant tokens to build concept slug
        let slugTokens = significantTokens.prefix(4)
        
        // Join with underscores
        let slug = slugTokens.joined(separator: "_")
        
        // Fallback if no significant tokens found
        return slug.isEmpty ? "item" : slug
    }
    
    /// Normalizes text by removing punctuation and collapsing whitespace.
    /// - Parameter text: Raw text to normalize
    /// - Returns: Normalized text (lowercase, no punctuation, single spaces)
    private static func normalizeText(_ text: String) -> String {
        // Remove punctuation (replace with spaces to preserve word boundaries)
        let withoutPunctuation = text.components(separatedBy: CharacterSet.punctuationCharacters)
            .joined(separator: " ")
        
        // Collapse whitespace (remove extra spaces, trim)
        let collapsed = withoutPunctuation.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        
        return collapsed
    }
    
    /// Checks if a token is significant for topic identity.
    /// Filters out:
    /// - Time/frequency tokens (checked FIRST, regardless of length)
    /// - Common stopwords (a, the, is, etc.) — reused from Canonicalizer
    /// - Very short words (< 3 characters)
    ///
    /// - Parameter token: The token to check
    /// - Returns: true if the token should be included in the concept slug
    private static func isSignificantToken(_ token: String) -> Bool {
        // CRITICAL: Check time/frequency tokens FIRST (before length check)
        // This ensures "last", "week", "day", etc. are ALWAYS filtered out
        // even if they meet the 3-char minimum length requirement
        if NormalizationRules.timeFrequencyTokens.contains(token) {
            return false
        }
        
        // Check against stopwords (reused from existing list)
        if stopwords.contains(token) {
            return false
        }
        
        // Filter out very short tokens (less than 3 chars) LAST
        // This comes after time/frequency check so short time words are caught
        guard token.count >= 3 else {
            return false
        }
        
        return true
    }
    
    // MARK: - Word Lists
    
    /// Common English stopwords that don't contribute to topic identity.
    /// Note: This list is reused from Canonicalizer design (as per Phase 2 spec).
    /// Time/frequency tokens are now in NormalizationRules.timeFrequencyTokens.
    private static let stopwords: Set<String> = [
        // Articles & Determiners
        "a", "an", "the",
        
        // Conjunctions
        "and", "or", "but", "nor", "yet", "so",
        
        // Prepositions
        "to", "from", "in", "on", "at", "by", "for", "with", "about",
        "as", "of", "up", "down", "out", "over", "under", "into",
        
        // Pronouns
        "i", "me", "my", "mine", "myself",
        "we", "us", "our", "ours", "ourselves",
        "you", "your", "yours", "yourself", "yourselves",
        "he", "him", "his", "himself",
        "she", "her", "hers", "herself",
        "it", "its", "itself",
        "they", "them", "their", "theirs", "themselves",
        
        // Demonstratives
        "this", "that", "these", "those",
        
        // Auxiliary verbs
        "be", "am", "is", "are", "was", "were", "been", "being",
        "have", "has", "had", "having",
        "do", "does", "did", "doing", "done",
        "will", "would", "shall", "should", "can", "could",
        "may", "might", "must",
        
        // Common verbs that add little meaning
        "go", "going", "get", "got", "getting", "make", "making",
        
        // Qualifiers & Intensifiers
        "very", "too", "also", "just", "now", "then", "than",
        "so", "such"
    ]
}
