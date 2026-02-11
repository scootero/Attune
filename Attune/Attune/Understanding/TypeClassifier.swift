//
//  TypeClassifier.swift
//  Attune
//
//  Provides deterministic type classification rules to ensure consistency across extractions.
//  Overwrites AI-generated type based on pattern matching in quotes and titles.
//

import Foundation

/// Service for classifying extracted item types using deterministic rules
struct TypeClassifier {
    
    // MARK: - Public API
    
    /// Classifies an extracted item's type using pattern matching and returns a new item with updated type.
    /// Rules (in priority order - conservative about commitments):
    /// 1. Time-bound event markers (meeting, appointment, explicit dates) -> "event"
    /// 2. Explicit commitment/obligation markers (I promised, I'm required to, explicit deadlines) -> "commitment"
    /// 3. State/observation markers (got, started, is, has, factual conditions) -> "state"
    /// 4. Intention/plan markers (I want to, I need to, I'm going to) -> "intention"
    /// 5. Default to AI's original type if no strong signal
    /// Note: "I need to" is treated as intention unless it's an explicit promise/obligation
    /// - Parameter item: The extracted item to classify
    /// - Returns: A new ExtractedItem with potentially updated type
    static func classify(_ item: ExtractedItem) -> ExtractedItem {
        // Combine quote and title for analysis
        let text = "\(item.sourceQuote) \(item.title)".lowercased()
        
        // Determine type based on patterns
        let classifiedType = determineType(text: text, originalType: item.type)
        
        // Return new item with updated type (only if changed)
        if classifiedType == item.type {
            return item
        }
        
        return ExtractedItem(
            id: item.id,
            sessionId: item.sessionId,
            segmentId: item.segmentId,
            segmentIndex: item.segmentIndex,
            type: classifiedType,
            title: item.title,
            summary: item.summary,
            categories: item.categories,
            confidence: item.confidence,
            strength: item.strength,
            sourceQuote: item.sourceQuote,
            contextBefore: item.contextBefore,
            contextAfter: item.contextAfter,
            fingerprint: item.fingerprint,
            reviewState: item.reviewState,
            reviewedAt: item.reviewedAt,
            calendarCandidate: item.calendarCandidate,
            createdAt: item.createdAt,
            extractedAt: item.extractedAt
        )
    }
    
    // MARK: - Private Helpers
    
    /// Determines the type based on text patterns (conservative about commitments)
    private static func determineType(text: String, originalType: String) -> String {
        // Priority 1: Event markers (time-bound occurrences with explicit dates/times)
        if containsEventMarkers(text) {
            return ExtractedItem.ItemType.event
        }
        
        // Priority 2: Explicit commitment markers (only true obligations/promises)
        if containsCommitmentMarkers(text) {
            return ExtractedItem.ItemType.commitment
        }
        
        // Priority 3: State markers (observations about current reality/facts)
        if containsStateMarkers(text) {
            return ExtractedItem.ItemType.state
        }
        
        // Priority 4: Intention markers (plans/desires, including "need to" without obligation)
        if containsIntentionMarkers(text) {
            return ExtractedItem.ItemType.intention
        }
        
        // No strong signal, keep AI's original classification
        return originalType
    }
    
    /// Checks for explicit commitment markers (only true obligations/promises)
    /// Conservative: "I need to" and "I have to" are NOT commitments unless explicitly tied to a promise
    private static func containsCommitmentMarkers(_ text: String) -> Bool {
        let commitmentPatterns = [
            "i promised",
            "i swore",
            "i committed to",
            "i'm obligated",
            "i'm required to",
            "i must by", // "I must by Friday" = deadline commitment
            "i have to by", // "I have to by next week" = deadline commitment
            "agreed to",
            "have to deliver",
            "need to deliver",
            "due by"
        ]
        
        return commitmentPatterns.contains { text.contains($0) }
    }
    
    /// Checks for event markers (time-bound occurrences)
    private static func containsEventMarkers(_ text: String) -> Bool {
        let eventPatterns = [
            "meeting",
            "appointment",
            "deadline",
            "scheduled",
            "calendar",
            "tomorrow",
            "next week",
            "next month",
            "on monday",
            "on tuesday",
            "on wednesday",
            "on thursday",
            "on friday",
            "on saturday",
            "on sunday",
            "at \\d", // "at 3pm", "at 10am"
            "due date"
        ]
        
        return eventPatterns.contains { pattern in
            if pattern.contains("\\") {
                // Regex pattern
                return text.range(of: pattern, options: .regularExpression) != nil
            } else {
                return text.contains(pattern)
            }
        }
    }
    
    /// Checks for state markers (current conditions/facts)
    private static func containsStateMarkers(_ text: String) -> Bool {
        let statePatterns = [
            "got a",
            "got the",
            "received",
            "started",
            "started a",
            "started the",
            "accepted",
            "accepted a",
            "accepted an",
            "is now",
            "has been",
            "have been",
            "currently",
            "right now",
            "these days",
            "lately",
            "recently",
            " is ",
            " has ",
            " was ",
            "feeling",
            "been feeling"
        ]
        
        return statePatterns.contains { text.contains($0) }
    }
    
    /// Checks for intention markers (plans/desires including "need to" without obligation)
    private static func containsIntentionMarkers(_ text: String) -> Bool {
        let intentionPatterns = [
            "want to",
            "would like to",
            "hoping to",
            "planning to",
            "thinking about",
            "considering",
            "might",
            "maybe",
            "wish i could",
            "trying to",
            "going to try",
            "i need to", // Intention unless explicitly a promise
            "i have to", // Intention unless explicitly a deadline
            "i should",
            "i'll",
            "i will",
            "gonna",
            "going to"
        ]
        
        return intentionPatterns.contains { text.contains($0) }
    }
}
