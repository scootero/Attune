//
//  CheckInExtractorService.swift
//  Attune
//
//  GPT extraction for check-in transcripts. Returns progress updates + optional mood.
//  Separate from ExtractorService — does NOT use ExtractedItem or ExtractionQueue.
//  Strict JSON output with defensive parsing. Slice 4.
//

import Foundation

/// Response from GPT check-in extraction. Defensive parsing for all optional fields.
struct CheckInExtractionResult {
    let updates: [CheckInUpdate]
    let moodLabel: String?
    let moodScore: Int?
}

/// Extracts progress updates and optional mood from check-in transcripts.
/// Uses OpenAI with strict JSON schema. Does NOT touch ExtractorService or ExtractedItem.
@MainActor
struct CheckInExtractorService {
    
    private static let defaultModel = "gpt-4o-mini"
    
    /// Extracts progress updates and mood from a check-in transcript.
    /// - Parameters:
    ///   - transcript: The transcribed check-in text
    ///   - intentions: Current IntentionSet intentions (for context)
    ///   - todaysTotals: Pre-computed totals per intentionId for today (from ProgressCalculator)
    ///   - checkInId: For logging
    /// - Returns: CheckInExtractionResult with updates and optional mood; empty on parse failure
    static func extract(
        transcript: String,
        intentions: [Intention],
        todaysTotals: [String: Double],
        checkInId: String
    ) async -> CheckInExtractionResult {
        
        AppLogger.log(AppLogger.AI, "checkin_extract id=\(AppLogger.shortId(checkInId)) chars=\(transcript.count) intentions=\(intentions.count)")
        
        let systemMessage = buildSystemMessage()
        let userMessage = buildUserMessage(
            transcript: transcript,
            intentions: intentions,
            todaysTotals: todaysTotals
        )
        let schema = buildSchema()
        
        // Debug log: ensure schema required matches properties (helps diagnose HTTP 400)
        if let schemaInner = schema["schema"] as? [String: Any],
           let props = schemaInner["properties"] as? [String: Any],
           let updatesDef = props["updates"] as? [String: Any],
           let itemsDef = updatesDef["items"] as? [String: Any] {
            let itemsPropsKeys = (itemsDef["properties"] as? [String: Any])?.keys.sorted().joined(separator: ",") ?? "nil"
            let itemsRequiredList = (itemsDef["required"] as? [String])?.joined(separator: ",") ?? "nil"
            AppLogger.log(AppLogger.AI, "checkin_schema_debug updates.items.properties=\(itemsPropsKeys) updates.items.required=\(itemsRequiredList)")
        }
        
        do {
            let jsonString = try await OpenAIClient.chatCompletion(
                model: defaultModel,
                systemMessage: systemMessage,
                userMessage: userMessage,
                schema: schema
            )
            
            let intentionIds = Set(intentions.map { $0.id })
            return parseResponse(jsonString: jsonString, checkInId: checkInId, intentionIds: intentionIds)
            
        } catch {
            AppLogger.log(AppLogger.ERR, "checkin_extract_failed id=\(AppLogger.shortId(checkInId)) error=\"\(error.localizedDescription)\"")
            return CheckInExtractionResult(updates: [], moodLabel: nil, moodScore: nil)
        }
    }
    
    // MARK: - Defensive Parsing
    
    /// Parses JSON response. Returns empty result on any parse failure (graceful degradation).
    private static func parseResponse(jsonString: String, checkInId: String, intentionIds: Set<String>) -> CheckInExtractionResult {
        guard let data = jsonString.data(using: .utf8) else {
            AppLogger.log(AppLogger.ERR, "checkin_extract_parse id=\(AppLogger.shortId(checkInId)) error=\"Invalid UTF8\"")
            return CheckInExtractionResult(updates: [], moodLabel: nil, moodScore: nil)
        }
        
        // Use flexible decoding: top-level and nested fields can be null/missing
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            AppLogger.log(AppLogger.ERR, "checkin_extract_parse id=\(AppLogger.shortId(checkInId)) error=\"Not valid JSON object\"")
            return CheckInExtractionResult(updates: [], moodLabel: nil, moodScore: nil)
        }
        
        // Parse updates array (defensive)
        var updates: [CheckInUpdate] = []
        if let updatesArray = json["updates"] as? [[String: Any]] {
            for item in updatesArray {
                if let update = parseUpdateItem(item, intentionIds: intentionIds) {
                    updates.append(update)
                }
            }
        }
        
        // Parse mood (optional). Clamp to 0-10; convert legacy -2..+2 if present.
        var moodScore = (json["moodScore"] as? NSNumber)?.intValue
        if let s = moodScore {
            moodScore = DailyMoodStore.clampMoodScore(s) ?? s
        }
        let moodLabel = json["moodLabel"] as? String
        
        AppLogger.log(AppLogger.AI, "checkin_extract_ok id=\(AppLogger.shortId(checkInId)) updates=\(updates.count) moodLabel=\(moodLabel ?? "nil") moodScore=\(moodScore?.description ?? "nil")")
        
        return CheckInExtractionResult(updates: updates, moodLabel: moodLabel, moodScore: moodScore)
    }
    
    /// Parses a single update object. Returns nil if invalid (intentionId not in set, bad updateType, etc.)
    private static func parseUpdateItem(_ item: [String: Any], intentionIds: Set<String>) -> CheckInUpdate? {
        guard let intentionId = item["intentionId"] as? String, intentionIds.contains(intentionId), // ensure intention is known
              let updateType = item["updateType"] as? String, // read update type
              (updateType == "INCREMENT" || updateType == "TOTAL"), // validate allowed types
              let amount = (item["amount"] as? NSNumber)?.doubleValue, // extract numeric amount
              let unit = item["unit"] as? String, // extract unit text
              let confidence = (item["confidence"] as? NSNumber)?.doubleValue else { // extract confidence score
            return nil // fail parsing if any required field missing or invalid
        }
        
        let evidence = item["evidence"] as? String // optional evidence quote
        
        let rawLocalTime = item["tookPlaceLocalTime"] as? [String: Any] // optional nested time components
        let tookPlaceLocalTime: CheckInUpdate.TookPlaceLocalTime? // holder for validated local time
        if let rawLocalTime { // only attempt parse when present
            let hour = (rawLocalTime["hour24"] as? NSNumber)?.intValue // read 24h hour
            let minute = (rawLocalTime["minute"] as? NSNumber)?.intValue // read minute
            if let hour, let minute { // ensure both components exist
                tookPlaceLocalTime = CheckInUpdate.TookPlaceLocalTime(hour24: hour, minute: minute) // build structured time
            } else {
                tookPlaceLocalTime = nil // drop if incomplete to stay safe
            }
        } else {
            tookPlaceLocalTime = nil // absent means fall back to createdAt later
        }
        
        let rawTimeInterpretation = item["timeInterpretation"] as? String // optional interpretation hint
        let allowedInterpretations = Set(["explicit_time", "just_now", "unspecified"]) // allowed values for safety
        let timeInterpretation = rawTimeInterpretation.flatMap { allowedInterpretations.contains($0) ? $0 : nil } // sanitize unknown strings
        
        return CheckInUpdate(
            intentionId: intentionId, // store validated intention id
            updateType: updateType, // store validated update type
            amount: max(0, amount),  // No negative amounts
            unit: unit.isEmpty ? "units" : unit, // default unit if empty
            confidence: min(1.0, max(0.0, confidence)), // clamp confidence into range
            evidence: evidence, // pass evidence through
            tookPlaceLocalTime: tookPlaceLocalTime, // pass optional local time
            timeInterpretation: timeInterpretation // pass sanitized interpretation
        )
    }
    
    // MARK: - Prompt Building
    
    private static func buildSystemMessage() -> String { // Builds system prompt with alias-aware rule to guide GPT mapping
        return """
You extract progress updates and optional mood from daily check-in transcripts.

Given the user's current intentions (with target values and units) and today's progress so far, identify any explicit progress mentioned in the transcript.

RULES:
- Only extract updates that clearly reference one of the provided intentions (match by intentionId).
- Titles and aliases are equivalent signals: if transcript mentions a title or any alias, map to that intentionId.
- updateType: "INCREMENT" when the user adds to their total (e.g., "I read 3 more pages").
- updateType: "TOTAL" when the user states an absolute total (e.g., "I've read 10 pages today").
- amount: numeric value only. Never negative.
- unit: must match the intention's unit (pages, minutes, sessions, etc.).
- confidence: 0.0 to 1.0 — how certain you are this extraction is correct.
- evidence: short exact quote from transcript that supports this update (optional).

TIME (required fields; use null when no explicit time):
- tookPlaceLocalTime: { "hour24": 0-23, "minute": 0-59 } when user states a clock time (e.g. "at 9 AM", "this morning at 9"); else null.
- timeInterpretation: "explicit_time" when tookPlaceLocalTime is set; "just_now" when user says "just now"/"just went"; "unspecified" when no time mentioned. Never null — use "unspecified" as default.

MOOD (optional, Slice A):
- moodLabel: one word or short phrase (e.g., "Calm", "Anxious", "Tired") or null.
- moodScore: integer 0 to 10 (0 = lowest, 10 = highest; 5 = neutral) or null.

Return ONLY valid JSON matching the schema. No markdown, no explanations.
If no progress or mood is clearly stated, return: {"updates": [], "moodLabel": null, "moodScore": null}
"""
    }
    
    private static func buildUserMessage(
        transcript: String,
        intentions: [Intention],
        todaysTotals: [String: Double]
    ) -> String {
        var msg = "CURRENT INTENTIONS:\n"
        for i in intentions {
            let aliasText = i.aliases.joined(separator: ",") // Render aliases as comma-separated list for prompt clarity
            msg += "- id: \(i.id) | title: \(i.title) | aliases: \(aliasText) | target: \(i.targetValue) \(i.unit) | timeframe: \(i.timeframe)\n" // Provide aliases alongside title so GPT can map semantic matches
        }
        msg += "\nTODAY'S TOTALS SO FAR (do not duplicate; add to or replace as appropriate):\n"
        for (id, total) in todaysTotals {
            msg += "- \(id): \(total)\n"
        }
        msg += "\nTRANSCRIPT:\n\(transcript)"
        return msg
    }
    
    // MARK: - JSON Schema (OpenAI strict)
    
    private static func buildSchema() -> [String: Any] {
        return [
            "name": "checkin_extraction",
            "schema": [
                "type": "object",
                "properties": [
                    "updates": [
                        "type": "array", // list of extracted updates
                        "items": [
                            "type": "object", // each update is an object
                            "properties": [
                                "intentionId": ["type": "string"], // target intention id
                                "updateType": ["type": "string"], // INCREMENT or TOTAL
                                "amount": ["type": "number"], // numeric amount
                                "unit": ["type": "string"], // measurement unit
                                "confidence": ["type": "number"], // confidence score
                                "evidence": ["type": ["string", "null"]], // optional evidence quote
                                "tookPlaceLocalTime": [ // optional local time components
                                    "type": ["object", "null"], // allow null or missing
                                    "properties": [
                                        "hour24": ["type": "integer"], // 0-23 hour component
                                        "minute": ["type": "integer"] // 0-59 minute component
                                    ],
                                    "required": ["hour24", "minute"], // require both when present
                                    "additionalProperties": false // block extra keys
                                ],
                                "timeInterpretation": [ // optional interpretation hint
                                    "type": ["string", "null"] // allow string or null
                                ]
                            ],
                            "required": ["intentionId", "updateType", "amount", "unit", "confidence", "evidence", "tookPlaceLocalTime", "timeInterpretation"], // OpenAI strict requires all props; use null for optional
                            "additionalProperties": false // prevent unexpected fields
                        ]
                    ],
                    "moodLabel": ["type": ["string", "null"]],
                    "moodScore": ["type": ["integer", "null"]]
                ],
                "required": ["updates", "moodLabel", "moodScore"],
                "additionalProperties": false
            ],
            "strict": true
        ]
    }
}
