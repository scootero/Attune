//
//  ExtractorService.swift
//  Pondera
//
//  Extraction service that calls OpenAI to convert segment transcripts into ExtractedItem candidates.
//  Uses structured outputs with "sparse by default" guardrail: returning zero items is valid.
//

import Foundation

/// Response structure from OpenAI matching our extraction schema
private struct ExtractionResponse: Codable {
    let items: [ExtractionItem]
    /// Optional for compatibility with a deployed Worker that predates mood
    /// extraction on Talk it out.
    let moodLabel: String?
    let moodScore: Int?
    
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

struct ListeningExtractionResult {
    let items: [ExtractedItem]
    let moodLabel: String?
    let moodScore: Int?

    static let empty = ListeningExtractionResult(items: [], moodLabel: nil, moodScore: nil)
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
    /// Returns an empty result if nothing is high-confidence and meaningful.
    /// - Parameters:
    ///   - transcriptText: Current segment transcript text
    ///   - priorContextText: Optional context from previous segment (last 2-3 sentences)
    ///   - sessionId: Parent session identifier
    ///   - segmentId: Parent segment identifier
    ///   - segmentIndex: Segment index within session
    /// - Returns: Extracted items plus an optional directly expressed mood.
    static func extractItems(
        transcriptText: String,
        priorContextText: String?,
        sessionId: String,
        segmentId: String,
        segmentIndex: Int,
        referenceDate: Date
    ) async -> ListeningExtractionResult {
        
        let sessionShort = AppLogger.shortId(sessionId)
        let charCount = transcriptText.count + (priorContextText?.count ?? 0)
        
        // Log extraction call
        AppLogger.log(AppLogger.AI, "extract_call session=\(sessionShort) seg=\(segmentIndex) chars=\(charCount)")
        
        // Build system message with instructions
        let systemMessage = buildSystemMessage()
        
        // Build user message with context + transcript
        let userMessage = buildUserMessage(
            transcriptText: transcriptText,
            priorContextText: priorContextText,
            referenceDate: referenceDate
        )
        
        // Build JSON schema for structured outputs
        let schema = buildExtractionSchema()
        
        // Try extraction (with one retry on decode failure)
        let result = await attemptExtraction(
            transcriptText: transcriptText,
            priorContextText: priorContextText,
            systemMessage: systemMessage,
            userMessage: userMessage,
            schema: schema,
            sessionId: sessionId,
            segmentId: segmentId,
            segmentIndex: segmentIndex,
            referenceDate: referenceDate,
            retryOnFailure: true
        )
        
        // Log success
        AppLogger.log(
            AppLogger.AI,
            "extract_ok session=\(sessionShort) seg=\(segmentIndex) items=\(result.items.count) moodLabel=\(result.moodLabel ?? "nil") moodScore=\(result.moodScore?.description ?? "nil")"
        )
        
        return result
    }
    
    // MARK: - Private Helpers
    
    /// Attempts extraction with optional retry on decode failure
    private static func attemptExtraction(
        transcriptText: String,
        priorContextText: String?,
        systemMessage: String,
        userMessage: String,
        schema: [String: Any],
        sessionId: String,
        segmentId: String,
        segmentIndex: Int,
        referenceDate: Date,
        retryOnFailure: Bool
    ) async -> ListeningExtractionResult {
        
        let sessionShort = AppLogger.shortId(sessionId)
        
        do {
            let jsonString: String
            if OpenAIClient.usesServerOwnedV2(.listening) {
                // Debug rollout: keep the existing segment and prior-context
                // inputs while the Worker owns the extraction policy.
                var body: [String: Any] = [
                    "transcript": transcriptText,
                    "referenceDateTime": iso8601Formatter.string(from: referenceDate),
                    "timeZone": TimeZone.current.identifier
                ]
                if let priorContextText, !priorContextText.isEmpty {
                    body["priorContext"] = priorContextText
                }
                do {
                    jsonString = try await OpenAIClient.serverOwnedTask(.listening, body: body)
                } catch OpenAIClientError.httpError(let statusCode, let responseBody)
                    where statusCode == 400 && responseBody?.contains("Unsupported request field") == true {
                    // Compatibility with a deployed Worker that predates the
                    // explicit temporal request fields. The proper contract is
                    // still used automatically as soon as that Worker is updated.
                    AppLogger.log(AppLogger.AI, "listening_temporal_contract_fallback session=\(sessionShort) seg=\(segmentIndex)")
                    var fallbackBody: [String: Any] = ["transcript": transcriptText]
                    fallbackBody["priorContext"] = legacyTemporalContext(
                        priorContextText: priorContextText,
                        referenceDate: referenceDate
                    )
                    jsonString = try await OpenAIClient.serverOwnedTask(.listening, body: fallbackBody)
                }
            } else {
                // Release fallback remains unchanged until v2 comparison is approved.
                jsonString = try await OpenAIClient.chatCompletion(
                    model: defaultModel,
                    systemMessage: systemMessage,
                    userMessage: userMessage,
                    schema: schema
                )
            }
            
            // Decode strict JSON response
            let data = jsonString.data(using: .utf8)!
            let decoder = JSONDecoder()
            let response = try decoder.decode(ExtractionResponse.self, from: data)
            
            // Map to ExtractedItem instances while keeping the optional mood
            // separate from Insights persistence.
            let items = response.items.map { item in
                mapToExtractedItem(
                    item: item,
                    sessionId: sessionId,
                    segmentId: segmentId,
                    segmentIndex: segmentIndex,
                    referenceDate: referenceDate
                )
            }
            return ListeningExtractionResult(
                items: items,
                moodLabel: response.moodLabel,
                moodScore: DailyMoodStore.clampMoodScore(response.moodScore)
            )
            
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
                    transcriptText: transcriptText,
                    priorContextText: priorContextText,
                    systemMessage: strongerSystemMessage,
                    userMessage: userMessage,
                    schema: schema,
                    sessionId: sessionId,
                    segmentId: segmentId,
                    segmentIndex: segmentIndex,
                    referenceDate: referenceDate,
                    retryOnFailure: false  // No second retry
                )
            }
            
            return .empty
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
- For event types, provide calendarCandidate whenever the words identify a date, a relative day, or a clock time.
  - suggestedTitle, startISO8601, endISO8601, isAllDay, notes
- Resolve "today", "tomorrow", weekdays, and other relative dates from the supplied REFERENCE DATE/TIME in its supplied TIME ZONE.
- If an event gives a clock time but no date, use the local calendar day of the reference date/time.
- If an event gives a date but no clock time, use yyyy-MM-dd for startISO8601, set endISO8601 to null, and isAllDay to false. This means "time not specified," not all-day.
- If neither a date nor clock time is stated or strongly implied, calendarCandidate may be null.

DAILY MOOD:
- moodLabel: one word or a short phrase describing the user's current feeling, or null.
- moodScore: the closest reasonable integer from 0 to 10, where 0 is lowest, 5 is neutral, and 10 is highest, or null.
- Capture mood only when the user directly describes their own current mood, feeling, happiness, or emotional state. A qualitative statement such as "I'm doing well" may be approximated.
- Do not infer mood merely because a positive or negative event happened.
- If the transcript contains multiple current mood statements, use the latest clear self-report in transcript order.
- Prior context can clarify the current transcript, but must not replace a newer mood stated in the current transcript.

Return ONLY valid JSON matching the schema. No markdown, no explanations.
If nothing meets the quality bar, return: {"items": [], "moodLabel": null, "moodScore": null}
"""
    }
    
    /// Builds the user message with optional prior context and transcript
    private static func buildUserMessage(
        transcriptText: String,
        priorContextText: String?,
        referenceDate: Date
    ) -> String {
        var message = temporalReference(referenceDate) + "\n\n"
        
        if let priorContext = priorContextText, !priorContext.isEmpty {
            message += "PRIOR CONTEXT (from previous segment):\n\(priorContext)\n\n"
        }
        
        message += "TRANSCRIPT:\n\(transcriptText)"
        
        return message
    }

    private static func temporalReference(_ referenceDate: Date) -> String {
        "REFERENCE DATE/TIME (recording metadata, not spoken words):\n" +
            "referenceDateTime: \(iso8601Formatter.string(from: referenceDate))\n" +
            "timeZone: \(TimeZone.current.identifier)"
    }

    private static func legacyTemporalContext(
        priorContextText: String?,
        referenceDate: Date
    ) -> String {
        var context = temporalReference(referenceDate)
        if let priorContextText, !priorContextText.isEmpty {
            context += "\n\nPREVIOUS SPOKEN CONTEXT:\n\(priorContextText)"
        }
        return context
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
                    ],
                    "moodLabel": ["type": ["string", "null"]],
                    "moodScore": ["type": ["integer", "null"]]
                ],
                "required": ["items", "moodLabel", "moodScore"],
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
        segmentIndex: Int,
        referenceDate: Date
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

        // Apply temporal fallback after deterministic type classification so an
        // item promoted to event still receives today/tomorrow/time handling.
        let normalizedCandidate = normalizedCalendarCandidate(
            classifiedItem.calendarCandidate,
            itemType: classifiedItem.type,
            sourceQuote: classifiedItem.sourceQuote,
            referenceDate: referenceDate
        )
        if classifiedItem.calendarCandidate?.startISO8601 == nil,
           let resolvedStart = normalizedCandidate?.startISO8601 {
            AppLogger.log(
                AppLogger.AI,
                "calendar_temporal_resolved session=\(AppLogger.shortId(sessionId)) seg=\(segmentIndex) has_time=\(resolvedStart.contains("T"))"
            )
        }
        let calendarReadyItem = replacingCalendarCandidate(
            in: classifiedItem,
            with: normalizedCandidate
        )
        
        // Phase 3: Apply strength scoring (overwrites AI strength with heuristic score)
        let scoredItem = applyStrengthScoring(calendarReadyItem)
        
        return scoredItem
    }

    private static func replacingCalendarCandidate(
        in item: ExtractedItem,
        with calendarCandidate: CalendarCandidate?
    ) -> ExtractedItem {
        ExtractedItem(
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
            fingerprint: item.fingerprint,
            reviewState: item.reviewState,
            reviewedAt: item.reviewedAt,
            calendarCandidate: calendarCandidate,
            createdAt: item.createdAt,
            extractedAt: item.extractedAt
        )
    }

    /// Deterministic safety net for the most important relative phrases. The
    /// model remains responsible for broader natural-language interpretation,
    /// while this guarantees today/tomorrow/weekday and explicit AM/PM times
    /// do not disappear when a provider returns a null calendar candidate.
    private static func normalizedCalendarCandidate(
        _ candidate: CalendarCandidate?,
        itemType: String,
        sourceQuote: String,
        referenceDate: Date
    ) -> CalendarCandidate? {
        if candidate?.startISO8601 != nil { return candidate }
        guard itemType == ExtractedItem.ItemType.event else { return candidate }

        let lowercased = sourceQuote.lowercased()
        let calendar = Calendar.autoupdatingCurrent
        let referenceDay = calendar.startOfDay(for: referenceDate)
        var scheduledDay: Date?

        if lowercased.range(of: #"\btomorrow\b"#, options: .regularExpression) != nil {
            scheduledDay = calendar.date(byAdding: .day, value: 1, to: referenceDay)
        } else if lowercased.range(of: #"\b(today|tonight)\b"#, options: .regularExpression) != nil {
            scheduledDay = referenceDay
        } else {
            let weekdays = [
                "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
                "thursday": 5, "friday": 6, "saturday": 7
            ]
            for (name, weekday) in weekdays where lowercased.range(of: #"\b\#(name)\b"#, options: .regularExpression) != nil {
                let searchStart = calendar.date(byAdding: .second, value: -1, to: referenceDay) ?? referenceDay
                scheduledDay = calendar.nextDate(
                    after: searchStart,
                    matching: DateComponents(weekday: weekday),
                    matchingPolicy: .nextTime,
                    direction: .forward
                )
                break
            }
        }

        let spokenTime = parsedSpokenTime(in: lowercased)
        if scheduledDay == nil, spokenTime != nil {
            scheduledDay = referenceDay
        }
        guard let scheduledDay else { return candidate }

        let startValue: String
        if let spokenTime {
            let start = calendar.date(
                bySettingHour: spokenTime.hour,
                minute: spokenTime.minute,
                second: 0,
                of: scheduledDay
            ) ?? scheduledDay
            startValue = iso8601Formatter.string(from: start)
        } else {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd"
            startValue = formatter.string(from: scheduledDay)
        }

        return CalendarCandidate(
            suggestedTitle: candidate?.suggestedTitle,
            startISO8601: startValue,
            endISO8601: candidate?.endISO8601,
            isAllDay: false,
            notes: candidate?.notes
        )
    }

    private static func parsedSpokenTime(in text: String) -> (hour: Int, minute: Int)? {
        if text.range(of: #"\bnoon\b"#, options: .regularExpression) != nil {
            return (12, 0)
        }
        if text.range(of: #"\bmidnight\b"#, options: .regularExpression) != nil {
            return (0, 0)
        }

        let pattern = #"\b([1-9]|1[0-2])(?::([0-5][0-9]))?\s*(a\.?m\.?|p\.?m\.?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              let hourRange = Range(match.range(at: 1), in: text),
              var hour = Int(text[hourRange]) else {
            return nil
        }

        var minute = 0
        if match.range(at: 2).location != NSNotFound,
           let minuteRange = Range(match.range(at: 2), in: text) {
            minute = Int(text[minuteRange]) ?? 0
        }
        guard let meridiemRange = Range(match.range(at: 3), in: text) else { return nil }
        let meridiem = text[meridiemRange].replacingOccurrences(of: ".", with: "")
        if meridiem == "pm", hour < 12 { hour += 12 }
        if meridiem == "am", hour == 12 { hour = 0 }
        return (hour, minute)
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
