//
//  ExtractorService.swift
//  Attune
//
//  Extraction service that calls OpenAI to convert segment transcripts into ExtractedItem candidates.
//  Uses structured outputs with "sparse by default" guardrail: returning zero items is valid.
//

import Foundation

/// Response structure from OpenAI matching our extraction schema
private struct ExtractionResponse: Codable {
    let items: [ExtractionItem]
    
    struct ExtractionItem: Codable {
        let type: String
        let title: String
        let summary: String
        let categories: [String]
        let confidence: Double
        let strength: Double
        let sourceQuote: String
        let contextBefore: String?
        let contextAfter: String?
        let fingerprint: String
        let calendarCandidate: CalendarCandidateData?
        
        struct CalendarCandidateData: Codable {
            let suggestedTitle: String?
            let startISO8601: String?
            let endISO8601: String?
            let isAllDay: Bool?
            let notes: String?
        }
    }
}

/// Service for extracting structured items from segment transcripts using LLM
struct ExtractorService {
    
    // MARK: - Configuration
    
    /// Default model for extraction
    private static let defaultModel = "gpt-4o-mini"
    
    /// ISO8601 date formatter for timestamps
    private static let iso8601Formatter = ISO8601DateFormatter()
    
    // MARK: - Public API
    
    /// Extracts candidate items from a segment transcript.
    /// Returns empty array if nothing is high-confidence and meaningful (sparse by default).
    /// - Parameters:
    ///   - transcriptText: Current segment transcript text
    ///   - priorContextText: Optional context from previous segment (last 2-3 sentences)
    ///   - sessionId: Parent session identifier
    ///   - segmentId: Parent segment identifier
    ///   - segmentIndex: Segment index within session
    /// - Returns: Array of ExtractedItem candidates (may be empty)
    static func extractItems(
        transcriptText: String,
        priorContextText: String?,
        sessionId: String,
        segmentId: String,
        segmentIndex: Int
    ) async -> [ExtractedItem] {
        
        let sessionShort = AppLogger.shortId(sessionId)
        let charCount = transcriptText.count + (priorContextText?.count ?? 0)
        
        // Log extraction call
        AppLogger.log(AppLogger.AI, "extract_call session=\(sessionShort) seg=\(segmentIndex) chars=\(charCount)")
        
        // Build system message with instructions
        let systemMessage = buildSystemMessage()
        
        // Build user message with context + transcript
        let userMessage = buildUserMessage(
            transcriptText: transcriptText,
            priorContextText: priorContextText
        )
        
        // Build JSON schema for structured outputs
        let schema = buildExtractionSchema()
        
        // Try extraction (with one retry on decode failure)
        let extractedItems = await attemptExtraction(
            systemMessage: systemMessage,
            userMessage: userMessage,
            schema: schema,
            sessionId: sessionId,
            segmentId: segmentId,
            segmentIndex: segmentIndex,
            retryOnFailure: true
        )
        
        // Log success
        AppLogger.log(
            AppLogger.AI,
            "extract_ok session=\(sessionShort) seg=\(segmentIndex) items=\(extractedItems.count)"
        )
        
        return extractedItems
    }
    
    // MARK: - Private Helpers
    
    /// Attempts extraction with optional retry on decode failure
    private static func attemptExtraction(
        systemMessage: String,
        userMessage: String,
        schema: [String: Any],
        sessionId: String,
        segmentId: String,
        segmentIndex: Int,
        retryOnFailure: Bool
    ) async -> [ExtractedItem] {
        
        let sessionShort = AppLogger.shortId(sessionId)
        
        do {
            // Call OpenAI with system + user messages
            let jsonString = try await OpenAIClient.chatCompletion(
                model: defaultModel,
                systemMessage: systemMessage,
                userMessage: userMessage,
                schema: schema
            )
            
            // Decode strict JSON response
            let data = jsonString.data(using: .utf8)!
            let decoder = JSONDecoder()
            let response = try decoder.decode(ExtractionResponse.self, from: data)
            
            // Map to ExtractedItem instances
            return response.items.map { item in
                mapToExtractedItem(
                    item: item,
                    sessionId: sessionId,
                    segmentId: segmentId,
                    segmentIndex: segmentIndex
                )
            }
            
        } catch {
            // Log decode failure
            AppLogger.log(
                AppLogger.ERR,
                "extract_decode_failed session=\(sessionShort) seg=\(segmentIndex) error=\"\(error.localizedDescription)\""
            )
            
            // Retry once with stronger system message if allowed
            if retryOnFailure {
                let strongerSystemMessage = systemMessage + "\n\nIMPORTANT: Return ONLY valid JSON matching the schema. No additional text."
                
                return await attemptExtraction(
                    systemMessage: strongerSystemMessage,
                    userMessage: userMessage,
                    schema: schema,
                    sessionId: sessionId,
                    segmentId: segmentId,
                    segmentIndex: segmentIndex,
                    retryOnFailure: false  // No second retry
                )
            }
            
            // Return empty array after exhausting retries
            return []
        }
    }
    
    /// Builds the system message with extraction instructions and guardrails
    private static func buildSystemMessage() -> String {
        return """
You are an extraction assistant that identifies meaningful items from voice transcripts.

Extract ONLY items that are:
- High-confidence (you're sure this is what the user meant)
- Meaningful (worth tracking or acting on)
- Clearly stated (not vague or implied)

SPARSE BY DEFAULT: Returning an empty items array is completely valid and preferred over low-quality extractions.

ALLOWED TYPES:
- "event": time-bound occurrences (meetings, appointments, deadlines)
- "intention": things the user plans or wants to do
- "commitment": promises or obligations to self or others
- "state": observations about current conditions, feelings, or situations

ALLOWED CATEGORIES (can assign multiple):
- "fitness_health": physical health, exercise, medical, sleep, nutrition
- "career_work": job, projects, professional development
- "money_finance": finances, purchases, investments, budgets
- "personal_growth": learning, skills, self-improvement, hobbies
- "relationships_social": family, friends, social connections
- "stress_load": stress, overwhelm, burnout, pressure
- "peace_wellbeing": calm, contentment, mental health, balance

REQUIRED TITLE (1–3 words, max 4 if needed):
- Use noun phrase / simplest phrasing
- Avoid filler words: "like", "felt", "start", "would", "going to", "want to"
- Avoid duplicate words: "New Puppy" not "New Puppy New Puppy"
- Prefer compound words if natural: "Workout" over "Work Out"
- Do NOT echo transcript phrasing verbatim
- Examples: "Workout", "Call Mom", "Doctor Appointment", "Budget Review"

REQUIRED PROVENANCE:
- sourceQuote: exact words from transcript
- contextBefore: a few words before the quote (if helpful)
- contextAfter: a few words after the quote (if helpful)

REQUIRED SCORES (0.0 to 1.0):
- confidence: how certain you are this extraction is CORRECT (not how important it is)
  → Score based on clarity and certainty of the extraction, not the item's significance
- strength: how important/impactful this item seems (this will be overridden by heuristics)

REQUIRED FINGERPRINT (best-effort concept label):
- fingerprint: a short concept label like "workout" or "call_mom" (your best guess)
  → Do NOT include time qualifiers (today, tomorrow, daily, weekly, etc.)
  → Do NOT attempt semantic grouping or synonym matching
  → Just provide a simple label for this specific mention

CALENDAR CANDIDATES:
- For event types, optionally provide calendarCandidate with:
  - suggestedTitle, startISO8601, endISO8601, isAllDay, notes
- Only include if date/time information is explicit or strongly implied

Return ONLY valid JSON matching the schema. No markdown, no explanations.
If nothing meets the quality bar, return: {"items": []}
"""
    }
    
    /// Builds the user message with optional prior context and transcript
    private static func buildUserMessage(
        transcriptText: String,
        priorContextText: String?
    ) -> String {
        var message = ""
        
        if let priorContext = priorContextText, !priorContext.isEmpty {
            message += "PRIOR CONTEXT (from previous segment):\n\(priorContext)\n\n"
        }
        
        message += "TRANSCRIPT:\n\(transcriptText)"
        
        return message
    }
    
    /// Builds the JSON schema for structured outputs
    private static func buildExtractionSchema() -> [String: Any] {
        return [
            "name": "items_extraction",
            "schema": [
                "type": "object",
                "properties": [
                    "items": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "type": ["type": "string"],
                                "title": ["type": "string"],
                                "summary": ["type": "string"],
                                "categories": [
                                    "type": "array",
                                    "items": ["type": "string"]
                                ],
                                "confidence": ["type": "number"],
                                "strength": ["type": "number"],
                                "sourceQuote": ["type": "string"],
                                "contextBefore": ["type": ["string", "null"]],
                                "contextAfter": ["type": ["string", "null"]],
                                "fingerprint": ["type": "string"],
                                "calendarCandidate": [
                                    "type": ["object", "null"],
                                    "properties": [
                                        "suggestedTitle": ["type": ["string", "null"]],
                                        "startISO8601": ["type": ["string", "null"]],
                                        "endISO8601": ["type": ["string", "null"]],
                                        "isAllDay": ["type": ["boolean", "null"]],
                                        "notes": ["type": ["string", "null"]]
                                    ],
                                    "required": ["suggestedTitle", "startISO8601", "endISO8601", "isAllDay", "notes"],
                                    "additionalProperties": false
                                ]
                            ],
                            "required": [
                                "type",
                                "title",
                                "summary",
                                "categories",
                                "confidence",
                                "strength",
                                "sourceQuote",
                                "contextBefore",
                                "contextAfter",
                                "fingerprint",
                                "calendarCandidate"
                            ],
                            "additionalProperties": false
                        ]
                    ]
                ],
                "required": ["items"],
                "additionalProperties": false
            ],
            "strict": true
        ]
    }
    
    /// Maps an extraction response item to an ExtractedItem model instance
    private static func mapToExtractedItem(
        item: ExtractionResponse.ExtractionItem,
        sessionId: String,
        segmentId: String,
        segmentIndex: Int
    ) -> ExtractedItem {
        
        let now = iso8601Formatter.string(from: Date())
        
        // Map calendar candidate if present
        let calendarCandidate: CalendarCandidate? = item.calendarCandidate.map { cal in
            CalendarCandidate(
                suggestedTitle: cal.suggestedTitle,
                startISO8601: cal.startISO8601,
                endISO8601: cal.endISO8601,
                isAllDay: cal.isAllDay,
                notes: cal.notes
            )
        }
        
        // Create initial extracted item with AI-generated values
        let initialItem = ExtractedItem(
            id: UUID().uuidString,
            sessionId: sessionId,
            segmentId: segmentId,
            segmentIndex: segmentIndex,
            type: item.type,
            title: item.title,
            summary: item.summary,
            categories: item.categories,
            confidence: item.confidence,
            strength: item.strength,
            sourceQuote: item.sourceQuote,
            contextBefore: item.contextBefore,
            contextAfter: item.contextAfter,
            fingerprint: item.fingerprint,
            reviewState: ExtractedItem.ReviewState.new,
            reviewedAt: nil,
            calendarCandidate: calendarCandidate,
            createdAt: now,
            extractedAt: now
        )
        
        // Apply canonicalization (overwrites fingerprint with stable key)
        let canonicalizedItem = Canonicalizer.canonicalize(initialItem)
        
        // Apply type classification (overwrites type with deterministic rules)
        let classifiedItem = TypeClassifier.classify(canonicalizedItem)
        
        // Phase 3: Apply strength scoring (overwrites AI strength with heuristic score)
        let scoredItem = applyStrengthScoring(classifiedItem)
        
        return scoredItem
    }
    
    /// Applies Phase 3 strength scoring to an extracted item.
    /// Overwrites the AI-generated strength value with a heuristic score based on linguistic patterns.
    /// - Parameter item: The extracted item to score
    /// - Returns: A new ExtractedItem with updated strength value
    private static func applyStrengthScoring(_ item: ExtractedItem) -> ExtractedItem {
        // Compute strength using heuristic scorer
        let computedStrength = StrengthScorer.computeStrength(
            title: item.title,
            sourceQuote: item.sourceQuote
        )
        
        // Return new item with updated strength
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
            strength: computedStrength,
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
}
