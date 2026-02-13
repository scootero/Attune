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
        guard let intentionId = item["intentionId"] as? String, intentionIds.contains(intentionId),
              let updateType = item["updateType"] as? String,
              (updateType == "INCREMENT" || updateType == "TOTAL"),
              let amount = (item["amount"] as? NSNumber)?.doubleValue,
              let unit = item["unit"] as? String,
              let confidence = (item["confidence"] as? NSNumber)?.doubleValue else {
            return nil
        }
        
        let evidence = item["evidence"] as? String
        
        return CheckInUpdate(
            intentionId: intentionId,
            updateType: updateType,
            amount: max(0, amount),  // No negative amounts
            unit: unit.isEmpty ? "units" : unit,
            confidence: min(1.0, max(0.0, confidence)),
            evidence: evidence
        )
    }
    
    // MARK: - Prompt Building
    
    private static func buildSystemMessage() -> String {
        return """
You extract progress updates and optional mood from daily check-in transcripts.

Given the user's current intentions (with target values and units) and today's progress so far, identify any explicit progress mentioned in the transcript.

RULES:
- Only extract updates that clearly reference one of the provided intentions (match by intentionId).
- updateType: "INCREMENT" when the user adds to their total (e.g., "I read 3 more pages").
- updateType: "TOTAL" when the user states an absolute total (e.g., "I've read 10 pages today").
- amount: numeric value only. Never negative.
- unit: must match the intention's unit (pages, minutes, sessions, etc.).
- confidence: 0.0 to 1.0 — how certain you are this extraction is correct.
- evidence: short exact quote from transcript that supports this update (optional).

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
            msg += "- id: \(i.id) | title: \(i.title) | target: \(i.targetValue) \(i.unit) | timeframe: \(i.timeframe)\n"
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
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "intentionId": ["type": "string"],
                                "updateType": ["type": "string"],
                                "amount": ["type": "number"],
                                "unit": ["type": "string"],
                                "confidence": ["type": "number"],
                                "evidence": ["type": ["string", "null"]]
                            ],
                            "required": ["intentionId", "updateType", "amount", "unit", "confidence", "evidence"],
                            "additionalProperties": false
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
