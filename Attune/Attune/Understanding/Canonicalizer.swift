//
//  Canonicalizer.swift
//  Attune
//
//  Generates stable canonical fingerprints for ExtractedItems to enable cross-session deduplication.
//  Overwrites the AI-generated fingerprint with a deterministic hash-based key.
//

import Foundation
import CryptoKit

/// Service for generating canonical fingerprints from extracted items
struct Canonicalizer {
    
    // MARK: - Public API
    
    /// Generates a canonical fingerprint for an extracted item and returns a new item with updated fingerprint.
    /// Format: "<topicStem>__<shortHash>" where hash is derived from stem only (not categories).
    /// Example: "wife_job__a1c9f2"
    /// The stem is built from significant words in the title and quote (lowercase, no punctuation, no stopwords).
    /// Categories are NOT included in hash to prevent key drift when AI assigns different categories.
    /// - Parameter item: The extracted item to canonicalize
    /// - Returns: A new ExtractedItem with canonical fingerprint
    static func canonicalize(_ item: ExtractedItem) -> ExtractedItem {
        // Build topic stem from title and quote
        let topicStem = buildTopicStem(title: item.title, quote: item.sourceQuote)
        
        // Generate short hash from stem only (no categories to prevent drift)
        let shortHash = generateShortHash(stem: topicStem)
        
        // Build canonical key
        let canonicalKey = "\(topicStem)__\(shortHash)"
        
        // Return new item with updated fingerprint
        return ExtractedItem(
            id: item.id,
            sessionId: item.sessionId,
            segmentId: item.segmentId,
            segmentIndex: item.segmentIndex,
            type: item.type,
            title: item.title,
            summary: item.summary,
            categories: item.categories,
            confidence: item.confidence,
            strength: item.strength,
            sourceQuote: item.sourceQuote,
            contextBefore: item.contextBefore,
            contextAfter: item.contextAfter,
            fingerprint: canonicalKey,
            reviewState: item.reviewState,
            reviewedAt: item.reviewedAt,
            calendarCandidate: item.calendarCandidate,
            createdAt: item.createdAt,
            extractedAt: item.extractedAt
        )
    }
    
    /// Generates a stable canonical title from a topic stem for display in Topics view.
    /// Prefers AI-provided title when available, falls back to Title Case stem.
    /// Example: "wife_job" -> "Wife Job" (if no AI title)
    /// Example: stem="work_out", aiTitle="Workout" -> "Workout"
    /// - Parameters:
    ///   - stem: The topic stem (e.g., "wife_job")
    ///   - aiTitle: Optional AI-generated title to prefer over stem
    /// - Returns: A human-readable title
    static func generateCanonicalTitle(from stem: String, aiTitle: String? = nil) -> String {
        // Prefer AI title if available and non-empty (trimmed)
        if let aiTitle = aiTitle?.trimmingCharacters(in: .whitespaces), !aiTitle.isEmpty {
            return aiTitle
        }
        
        // Fallback: convert stem to Title Case
        let words = stem.split(separator: "_").map { word in
            word.prefix(1).uppercased() + word.dropFirst()
        }
        
        return words.joined(separator: " ")
    }
    
    /// Determines if a new title is objectively better than an existing one.
    /// A title is "better" if it's more specific, longer, and doesn't contain filler words.
    /// - Parameters:
    ///   - newTitle: The candidate new title
    ///   - existingTitle: The current title
    /// - Returns: true if newTitle should replace existingTitle
    static func isBetterTitle(_ newTitle: String, than existingTitle: String) -> Bool {
        // Strip whitespace for comparison
        let new = newTitle.trimmingCharacters(in: .whitespaces)
        let existing = existingTitle.trimmingCharacters(in: .whitespaces)
        
        // Don't replace with empty
        if new.isEmpty {
            return false
        }
        
        // Filler words that indicate a vague title
        let fillerWords = ["impact", "thing", "stuff", "situation", "update", "about"]
        let newLower = new.lowercased()
        
        // Reject titles that are mostly filler
        for filler in fillerWords {
            if newLower.hasSuffix(filler) || newLower == filler {
                return false
            }
        }
        
        // Prefer longer, more specific titles (but not excessively long)
        let newWordCount = new.split(separator: " ").count
        let existingWordCount = existing.split(separator: " ").count
        
        // Title is better if it's more descriptive (2-6 words ideal)
        if newWordCount > existingWordCount && newWordCount <= 6 {
            return true
        }
        
        // Don't replace a good title with a shorter one
        if newWordCount < existingWordCount {
            return false
        }
        
        // Same length - keep existing (stability)
        return false
    }
    
    // MARK: - Private Helpers
    
    /// Builds a normalized topic stem from title ONLY using linguistic normalization.
    /// CRITICAL FIX: Uses title only, NOT quote, to ensure stable fingerprints.
    /// The quote contains variable context that causes key drift.
    /// Does NOT apply semantic mappings - the AI should handle semantic equivalence in its fingerprints.
    private static func buildTopicStem(title: String, quote: String) -> String {
        // Use ONLY title for fingerprint generation (not quote)
        // This ensures consistent fingerprints regardless of quote variations
        let combinedText = title.lowercased()
        
        // Normalize: remove punctuation, collapse whitespace
        let normalized = normalizText(combinedText)
        
        // Apply phrase replacements (e.g., "work out" → "workout")
        let withPhraseReplacements = NormalizationRules.applyPhraseReplacements(normalized)
        
        // Extract significant words (not stopwords)
        let words = withPhraseReplacements.split(separator: " ").map(String.init)
        let stemWords = words.filter { isSignificantWord($0) }
        
        // Dedupe within first 4 words (preserve order)
        var seen = Set<String>()
        let uniqueStemWords = stemWords.prefix(4).filter { word in
            if seen.contains(word) {
                return false
            } else {
                seen.insert(word)
                return true
            }
        }
        
        // Build stem from deduped significant words
        let stem = uniqueStemWords.joined(separator: "_")
        
        // Fallback if no significant words found
        return stem.isEmpty ? "item" : stem
    }
    
    /// Normalizes text by removing punctuation and collapsing whitespace
    private static func normalizText(_ text: String) -> String {
        // Remove punctuation
        let withoutPunctuation = text.components(separatedBy: CharacterSet.punctuationCharacters).joined(separator: " ")
        
        // Collapse whitespace
        let collapsed = withoutPunctuation.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        
        return collapsed
    }
    
    /// Checks if a word is significant (not a stopword or time/frequency token)
    /// CRITICAL: Must filter time/frequency tokens to prevent "job promotion last week"
    /// from creating different keys like "job_promotion_last" vs "job_promotion"
    private static func isSignificantWord(_ word: String) -> Bool {
        // Check time/frequency tokens FIRST (before length check)
        // This ensures "last", "week", "today", etc. are ALWAYS filtered
        if NormalizationRules.timeFrequencyTokens.contains(word) {
            return false
        }
        
        let stopwords = Set([
            "a", "an", "the", "and", "or", "but", "is", "are", "was", "were",
            "be", "been", "being", "have", "has", "had", "do", "does", "did",
            "will", "would", "should", "could", "may", "might", "must",
            "i", "me", "my", "mine", "we", "us", "our", "ours",
            "you", "your", "yours", "he", "him", "his", "she", "her", "hers",
            "it", "its", "they", "them", "their", "theirs",
            "this", "that", "these", "those",
            "to", "from", "in", "on", "at", "by", "for", "with", "about",
            "as", "of", "up", "down", "out", "over", "under",
            "so", "just", "now", "then", "than", "very", "too", "also",
            "am", "going", "go", "get", "got"
        ])
        
        return word.count > 2 && !stopwords.contains(word)
    }
    
    /// Generates a short hash (6 characters) from stem only
    /// Categories are deliberately excluded to prevent key drift when AI assigns different categories
    private static func generateShortHash(stem: String) -> String {
        // Hash input is stem only (no categories)
        let hashInput = stem
        
        // Generate SHA256 hash
        let data = Data(hashInput.utf8)
        let hash = SHA256.hash(data: data)
        
        // Convert to hex string and take first 6 characters
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        return String(hashString.prefix(6))
    }
}
