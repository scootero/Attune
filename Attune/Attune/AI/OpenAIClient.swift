//
//  OpenAIClient.swift
//  Attune
//
//  Minimal client for OpenAI Chat Completions via Attune's Cloudflare proxy.
//  POSTs to /v1/chat/completions with json_schema response format.
//

import Foundation

/// Errors that can occur during OpenAI API calls
enum OpenAIClientError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
    case timeout
    case networkError(Error)
    case decodingError(Error)
    /// User has not accepted the AI & privacy disclosure yet.
    case privacyConsentRequired
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from OpenAI API"
        case .httpError(let code, let body):
            return "HTTP \(code): \(body ?? "no body")"
        case .timeout:
            return "Request timed out"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .privacyConsentRequired:
            return "AI privacy consent is required before sending transcripts"
        }
    }
}

/// Response structure from OpenAI Chat Completions API
struct OpenAIChatResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    
    struct Choice: Codable {
        let index: Int
        let message: Message
        let finishReason: String?
        
        enum CodingKeys: String, CodingKey {
            case index
            case message
            case finishReason = "finish_reason"
        }
    }
    
    struct Message: Codable {
        let role: String
        let content: String?
    }
}

/// Minimal client for OpenAI Chat Completions via Attune's Cloudflare proxy.
/// The real OpenAI key stays on the server; the app only sends appProxyToken.
struct OpenAIClient {

    /// Server-owned task routes used during the staged v2 migration.
    /// Keep each feature opt-in separate so Debug testing cannot silently move
    /// every AI workflow at once. Release builds remain on the proven v1 route
    /// until the corresponding task has been compared and approved.
    enum ServerOwnedTask: String {
        case intentions = "/v2/intentions/parse"
        case checkIn = "/v2/check-ins/extract"
        case listening = "/v2/listening/extract"
    }
    
    // MARK: - Configuration
    
    /// Proxy base URL from Secrets (Worker that forwards to OpenAI).
    private static var baseURL: String { Secrets.proxyBaseURL }
    
    /// Default timeout interval (30 seconds)
    private static let timeoutInterval: TimeInterval = 30.0

    static func usesServerOwnedV2(_ task: ServerOwnedTask) -> Bool {
        #if DEBUG
        // Keep every feature independently switchable during physical-device rollout.
        let useV2Intentions = true
        let useV2CheckIns = true
        let useV2Listening = true

        switch task {
        case .intentions:
            return useV2Intentions
        case .checkIn:
            return useV2CheckIns
        case .listening:
            return useV2Listening
        }
        #else
        return false
        #endif
    }
    
    // MARK: - Public API

    /// Calls a server-owned v2 task and returns its direct structured JSON.
    /// The Worker—not the app—chooses the model, prompts, schema, and limits.
    static func serverOwnedTask(
        _ task: ServerOwnedTask,
        body: [String: Any]
    ) async throws -> String {
        guard AIPrivacyConsent.hasAccepted else {
            throw OpenAIClientError.privacyConsentRequired
        }

        let startTime = Date()
        let url = URL(string: "\(baseURL)\(task.rawValue)")!
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Secrets.appProxyToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        AppLogger.log(AppLogger.AI, "v2_request_start task=\(task.rawValue) body_bytes=\(request.httpBody?.count ?? 0)")
        let (data, response) = try await URLSession.shared.data(for: request)
        let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)

        guard let httpResponse = response as? HTTPURLResponse else {
            AppLogger.log(AppLogger.ERR, "v2_request_failed task=\(task.rawValue) error=\"invalid response type\"")
            throw OpenAIClientError.invalidResponse
        }

        AppLogger.log(
            AppLogger.AI,
            "v2_response_received task=\(task.rawValue) status=\(httpResponse.statusCode) ms=\(elapsedMs) bytes=\(data.count)"
        )

        guard (200...299).contains(httpResponse.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8)
            AppLogger.log(
                AppLogger.ERR,
                "v2_request_failed task=\(task.rawValue) status=\(httpResponse.statusCode) ms=\(elapsedMs) error=\"\(bodyString ?? "no body")\""
            )
            throw OpenAIClientError.httpError(statusCode: httpResponse.statusCode, body: bodyString)
        }

        guard httpResponse.value(forHTTPHeaderField: "X-Attune-Contract-Version") == "1",
              let jsonString = String(data: data, encoding: .utf8) else {
            AppLogger.log(AppLogger.ERR, "v2_request_failed task=\(task.rawValue) error=\"invalid contract response\"")
            throw OpenAIClientError.invalidResponse
        }

        return jsonString
    }
    
    /// Calls OpenAI Chat Completions API with structured output (json_schema).
    /// - Parameters:
    ///   - model: OpenAI model name (e.g., "gpt-4o-mini", "gpt-4o")
    ///   - inputText: User message text to send
    ///   - schema: JSON Schema definition as dictionary (must include name, schema, strict fields)
    /// - Returns: The decoded content string from the assistant's message
    /// - Throws: OpenAIClientError on failure
    static func chatCompletion(
        model: String,
        inputText: String,
        schema: [String: Any]
    ) async throws -> String {
        
        // Block network AI until the user accepts the first-launch disclosure.
        guard AIPrivacyConsent.hasAccepted else {
            throw OpenAIClientError.privacyConsentRequired
        }
        
        let startTime = Date()
        let userChars = inputText.count
        
        // Extract schema name for logging
        let schemaName = schema["name"] as? String ?? "unknown"
        
        // Log high-level request summary
        AppLogger.log(AppLogger.AI, "request_start model=\(model) user_chars=\(userChars) schema=\(schemaName)")
        
        // Build request through Attune proxy (never call api.openai.com from the device)
        let url = URL(string: "\(baseURL)/v1/chat/completions")!
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        
        // Headers (never log the Authorization header) — app proxy token, not OpenAI key
        request.setValue("Bearer \(Secrets.appProxyToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Request body
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": inputText]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": schema
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Execute request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
        
        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            AppLogger.log(AppLogger.ERR, "request_failed error=\"invalid response type\"")
            throw OpenAIClientError.invalidResponse
        }
        
        // Log response status and timing
        AppLogger.log(AppLogger.AI, "response_received status=\(httpResponse.statusCode) ms=\(elapsedMs) bytes=\(data.count)")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8)
            AppLogger.log(
                AppLogger.ERR,
                "request_failed status=\(httpResponse.statusCode) ms=\(elapsedMs) error=\"\(bodyString ?? "no body")\""
            )
            throw OpenAIClientError.httpError(statusCode: httpResponse.statusCode, body: bodyString)
        }
        
        // Full AI JSON only in Debug — avoid persisting transcripts/insights in Release logs.
        #if DEBUG
        if let responseString = String(data: data, encoding: .utf8) {
            AppLogger.log(AppLogger.AI, "response_body: \(responseString)")
        }
        #endif
        
        // Decode response
        let decoder = JSONDecoder()
        let chatResponse: OpenAIChatResponse
        
        do {
            chatResponse = try decoder.decode(OpenAIChatResponse.self, from: data)
        } catch {
            AppLogger.log(AppLogger.ERR, "request_failed error=\"decoding failed: \(error.localizedDescription)\"")
            throw OpenAIClientError.decodingError(error)
        }
        
        // Extract content from first choice
        guard let content = chatResponse.choices.first?.message.content else {
            AppLogger.log(AppLogger.ERR, "request_failed error=\"no content in response\"")
            throw OpenAIClientError.invalidResponse
        }
        
        // Log success with short preview only (not full content)
        let contentPreview = AppLogger.previewText(content, wordLimit: 10)
        AppLogger.log(AppLogger.AI, "request_done status=\(httpResponse.statusCode) ms=\(elapsedMs) content_preview=\"\(contentPreview)\"")
        
        return content
    }
    
    /// Calls OpenAI Chat Completions API with structured output (json_schema) using separate system and user messages.
    /// - Parameters:
    ///   - model: OpenAI model name (e.g., "gpt-4o-mini", "gpt-4o")
    ///   - systemMessage: System message containing instructions for the model
    ///   - userMessage: User message containing the actual content to process
    ///   - schema: JSON Schema definition as dictionary (must include name, schema, strict fields)
    /// - Returns: The decoded content string from the assistant's message
    /// - Throws: OpenAIClientError on failure
    static func chatCompletion(
        model: String,
        systemMessage: String,
        userMessage: String,
        schema: [String: Any]
    ) async throws -> String {
        
        // Block network AI until the user accepts the first-launch disclosure.
        guard AIPrivacyConsent.hasAccepted else {
            throw OpenAIClientError.privacyConsentRequired
        }
        
        let startTime = Date()
        let systemChars = systemMessage.count
        let userChars = userMessage.count
        
        // Extract schema name for logging
        let schemaName = schema["name"] as? String ?? "unknown"
        
        // Log high-level request summary
        AppLogger.log(AppLogger.AI, "request_start model=\(model) system_chars=\(systemChars) user_chars=\(userChars) schema=\(schemaName)")
        
        // Build request through Attune proxy (never call api.openai.com from the device)
        let url = URL(string: "\(baseURL)/v1/chat/completions")!
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        
        // Headers (never log the Authorization header) — app proxy token, not OpenAI key
        request.setValue("Bearer \(Secrets.appProxyToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Request body
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemMessage],
                ["role": "user", "content": userMessage]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": schema
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Execute request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
        
        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            AppLogger.log(AppLogger.ERR, "request_failed error=\"invalid response type\"")
            throw OpenAIClientError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8)
            AppLogger.log(
                AppLogger.ERR,
                "request_failed status=\(httpResponse.statusCode) ms=\(elapsedMs) error=\"\(bodyString ?? "no body")\""
            )
            throw OpenAIClientError.httpError(statusCode: httpResponse.statusCode, body: bodyString)
        }
        
        // Decode response
        let decoder = JSONDecoder()
        let chatResponse: OpenAIChatResponse
        
        do {
            chatResponse = try decoder.decode(OpenAIChatResponse.self, from: data)
        } catch {
            AppLogger.log(AppLogger.ERR, "request_failed error=\"decoding failed: \(error.localizedDescription)\"")
            throw OpenAIClientError.decodingError(error)
        }
        
        // Extract content from first choice
        guard let content = chatResponse.choices.first?.message.content else {
            AppLogger.log(AppLogger.ERR, "request_failed error=\"no content in response\"")
            throw OpenAIClientError.invalidResponse
        }
        
        // Log response summary; full content only in Debug builds.
        AppLogger.log(AppLogger.AI, "response_received status=\(httpResponse.statusCode) ms=\(elapsedMs) content_chars=\(content.count)")
        #if DEBUG
        AppLogger.log(AppLogger.AI, "response_content: \(content)")
        #endif
        
        return content
    }
}
