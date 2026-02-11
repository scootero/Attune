//
//  OpenAIClient.swift
//  Attune
//
//  Minimal client for OpenAI Chat Completions API with Structured Outputs.
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

/// Minimal client for OpenAI Chat Completions API with Structured Outputs
struct OpenAIClient {
    
    // MARK: - Configuration
    
    /// OpenAI API base URL
    private static let baseURL = "https://api.openai.com/v1"
    
    /// Default timeout interval (30 seconds)
    private static let timeoutInterval: TimeInterval = 30.0
    
    // MARK: - Public API
    
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
        
        let startTime = Date()
        let userChars = inputText.count
        
        // Extract schema name for logging
        let schemaName = schema["name"] as? String ?? "unknown"
        
        // Log high-level request summary
        AppLogger.log(AppLogger.AI, "request_start model=\(model) user_chars=\(userChars) schema=\(schemaName)")
        
        // Build request
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        
        // Headers (never log the Authorization header)
        request.setValue("Bearer \(Secrets.openAIKey)", forHTTPHeaderField: "Authorization")
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
        
        // Log full response body
        if let responseString = String(data: data, encoding: .utf8) {
            AppLogger.log(AppLogger.AI, "response_body: \(responseString)")
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
        
        // Log success with content preview
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
        
        let startTime = Date()
        let systemChars = systemMessage.count
        let userChars = userMessage.count
        
        // Extract schema name for logging
        let schemaName = schema["name"] as? String ?? "unknown"
        
        // Log high-level request summary
        AppLogger.log(AppLogger.AI, "request_start model=\(model) system_chars=\(systemChars) user_chars=\(userChars) schema=\(schemaName)")
        
        // Build request
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        
        // Headers (never log the Authorization header)
        request.setValue("Bearer \(Secrets.openAIKey)", forHTTPHeaderField: "Authorization")
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
        
        // Log response summary with model data structure
        AppLogger.log(AppLogger.AI, "response_received status=\(httpResponse.statusCode) ms=\(elapsedMs) content_chars=\(content.count)")
        AppLogger.log(AppLogger.AI, "response_content: \(content)")
        
        return content
    }
}
