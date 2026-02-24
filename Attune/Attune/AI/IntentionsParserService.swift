// IntentionsParserService.swift // explains the file purpose
// Attune // keeps project context consistent
// Calls OpenAI to convert a transcript into structured intentions with strict JSON schema. // summarizes behavior
import Foundation // needed for JSON parsing and data structures

/// Errors specific to parsing intentions from the LLM response. // documents error enum role
enum IntentionsParserError: LocalizedError { // defines custom parser errors
    case invalidJSON // signals when JSON cannot be parsed
    case missingIntentionsArray // signals when required intentions array is absent
    
    var errorDescription: String? { // provides human-readable descriptions
        switch self { // select message per case
        case .invalidJSON: return "Response was not valid JSON" // explanation for invalid JSON
        case .missingIntentionsArray: return "No intentions were returned" // explanation for missing array
        } // end switch
    } // end description
} // end enum

/// Service that sends transcripts to OpenAI and returns normalized parsed intentions. // explains struct purpose
struct IntentionsParserService { // encapsulates parsing behavior
    private static let defaultModel = "gpt-4o-mini" // preferred model aligned with existing usage
    
    /// Parses a transcript into structured intentions via OpenAI with JSON schema. // documents function role
    static func parse(transcript: String) async throws -> [ParsedIntention] { // entry point for callers
        let systemMessage = buildSystemMessage() // prepare system prompt with rules
        let userMessage = buildUserMessage(transcript: transcript) // prepare user prompt with transcript + contract
        let schema = buildSchema() // build strict JSON schema
        
        let jsonString = try await OpenAIClient.chatCompletion( // call OpenAI client for structured output
            model: defaultModel, // specify model name
            systemMessage: systemMessage, // pass system prompt
            userMessage: userMessage, // pass user prompt
            schema: schema // provide strict schema
        ) // end call
        
        return try parseResponse(jsonString: jsonString) // parse JSON string into ParsedIntentions
    } // end parse
    
    /// Parses JSON text into ParsedIntentions with normalization and defaults. // explains helper responsibility
    private static func parseResponse(jsonString: String) throws -> [ParsedIntention] { // handles decoding logic
        guard let data = jsonString.data(using: .utf8) else { throw IntentionsParserError.invalidJSON } // ensure UTF8 data
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw IntentionsParserError.invalidJSON } // decode to dictionary
        guard let items = root["intentions"] as? [[String: Any]] else { throw IntentionsParserError.missingIntentionsArray } // extract intentions array
        
        var results: [ParsedIntention] = [] // collect parsed intentions
        
        for item in items { // iterate over each raw intention
            guard let rawTitle = item["title"] as? String else { continue } // skip when title missing
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines) // clean up spacing
            guard !title.isEmpty else { continue } // skip empty titles
            
            let target = (item["target"] as? NSNumber)?.doubleValue // optional numeric target
            let rawUnit = item["unit"] as? String // optional raw unit
            let normalizedUnit = normalizeUnit(rawUnit) // map to canonical unit with defaults
            let category = item["category"] as? String // optional category string
            let notes = item["notes"] as? String // optional notes string
            
            let parsed = ParsedIntention( // build ParsedIntention with defaults
                title: title, // assign cleaned title
                target: target ?? 1, // default missing targets to 1 per plan
                unit: normalizedUnit, // assign normalized unit (never nil)
                category: category?.isEmpty == false ? category : nil, // drop empty category
                notes: notes?.isEmpty == false ? notes : nil // drop empty notes
            ) // end initializer
            results.append(parsed) // store parsed item
        } // end loop
        
        return results // return parsed list (possibly empty)
    } // end parseResponse
    
    /// Normalizes unit strings to the supported vocabulary, defaulting to \"times\". // documents normalization rule
    private static func normalizeUnit(_ unit: String?) -> String { // maps units safely
        guard let unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !unit.isEmpty else { return "times" } // default when missing or empty
        switch unit { // map common variants to canonical forms
        case "minute", "minutes", "min": return "minutes" // normalize minute variants
        case "page", "pages": return "pages" // normalize page variants
        case "time", "times": return "times" // normalize times variants
        case "mile", "miles", "mi": return "miles" // normalize mile variants
        case "step", "steps": return "steps" // normalize step variants
        case "session", "sessions": return "sessions" // retain sessions as known option
        case "rep", "reps": return "reps" // retain reps as known option
        case "cup", "cups": return "cups" // retain cups as known option
        case "glass", "glasses": return "glasses" // retain glasses as known option
        default: return "times" // fallback for unknown units
        } // end switch
    } // end normalizeUnit
    
    /// Builds system message instructing strict JSON output for intentions. // explains prompt helper
    private static func buildSystemMessage() -> String { // constructs system prompt
        """
You convert a user’s spoken intentions into structured JSON for an intentions app. Output JSON only. // directive for JSON-only output
Unit normalization rules: minutes/min -> \"minutes\"; pages/page -> \"pages\"; times/time -> \"times\"; miles/mi -> \"miles\"; steps -> \"steps\"; sessions -> \"sessions\"; reps -> \"reps\"; cups -> \"cups\"; glasses -> \"glasses\". Unknown -> \"times\". // embeds normalization guidance
Category inference: fitness/health -> fitness_health; work/coding/business -> career_work; money/budget -> money_finance; learning/reading -> personal_growth; social/friends/date -> relationships_social; stress/overwhelm -> stress_load; calm/meditation/sleep -> peace_wellbeing; if uncertain -> null. // embeds category mapping guidance
"""
        // end multiline string marker placed on its own line to satisfy Swift rules
    } // end buildSystemMessage
    
    /// Builds user message containing transcript and expected JSON contract. // documents user prompt helper
    private static func buildUserMessage(transcript: String) -> String { // constructs user message
        """
Transcript:
\(transcript)

Output JSON schema:
{
  "intentions": [
    {
      "title": "Walk",
      "target": 20,
      "unit": "minutes",
      "category": "fitness_health",
      "notes": null
    }
  ]
}
Rules:
- Provide an array of intentions (can be empty when nothing is found).
- title: required string.
- target: number; if missing default to 1.
- unit: normalized string; if missing default to "times".
- category: best-effort from allowed categories; null when uncertain.
- notes: optional; null when none.
Return JSON only. // detailed contract plus rules for the model
"""
        // end multiline string marker placed on its own line to satisfy Swift rules
    } // end buildUserMessage
    
    /// Builds the strict JSON schema used by OpenAI structured outputs. // describes schema helper
    private static func buildSchema() -> [String: Any] { // returns schema dictionary
        [
            "name": "intentions_parse", // schema name for logging
            "schema": [ // top-level schema definition
                "type": "object", // root is an object
                "properties": [ // root properties
                    "intentions": [ // intentions array definition
                        "type": "array", // array type
                        "items": [ // each array item schema
                            "type": "object", // item is object
                            "properties": [ // item properties
                                "title": ["type": "string"], // required title string
                                "target": ["type": ["number", "null"]], // optional numeric target
                                "unit": ["type": ["string", "null"]], // optional unit string
                                "category": ["type": ["string", "null"]], // optional category string
                                "notes": ["type": ["string", "null"]] // optional notes string
                            ], // end properties
                            "required": ["title", "target", "unit", "category", "notes"], // enforce presence (nullable allowed)
                            "additionalProperties": false // block unexpected fields
                        ] // end items object
                    ] // end intentions property
                ], // end root properties
                "required": ["intentions"], // require intentions array
                "additionalProperties": false // block extra root fields
            ], // end schema
            "strict": true // enforce strict mode
        ] // end dictionary
    } // end buildSchema
} // end struct
