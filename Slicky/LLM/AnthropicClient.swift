import Foundation

final class AnthropicClient {
    static let shared = AnthropicClient()
    private init() {}

    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"

    // MARK: - Streaming

    /// Streams text tokens from the Anthropic Messages API. Throws when the
    /// model returned no tokens, finished with a problematic stop_reason, or
    /// the SSE stream emitted an explicit error event.
    func stream(
        systemPrompt: String,
        userMessage: String,
        model: String,
        maxTokens: Int = 4096,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try self.buildRequest(
                        systemPrompt: systemPrompt,
                        userMessage: userMessage,
                        model: model,
                        maxTokens: maxTokens,
                        apiKey: apiKey
                    )

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }

                    if httpResponse.statusCode != 200 {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        NSLog("Slicky Anthropic %d: %@", httpResponse.statusCode, body)
                        if let data = body.data(using: .utf8),
                           let apiError = try? JSONDecoder().decode(AnthropicError.self, from: data) {
                            throw apiError
                        }
                        throw URLError(.badServerResponse)
                    }

                    var parser = SSEParser()
                    var totalChars = 0
                    var stopReason: String?
                    for try await line in bytes.lines {
                        switch parser.processLine(line) {
                        case .textDelta(let token):
                            totalChars += token.count
                            continuation.yield(token)
                        case .stopReason(let reason):
                            stopReason = reason
                        case .errorPayload(let message):
                            NSLog("Slicky stream error event: %@", message)
                            throw AnthropicStreamError(kind: .apiError, message: message)
                        case .ignore:
                            break
                        }
                    }

                    if totalChars == 0 {
                        let detail = stopReason.map { "stop_reason=\($0)" } ?? "no tokens received"
                        NSLog("Slicky empty stream: %@ (model=%@)", detail, model)
                        throw AnthropicStreamError(kind: .noContent, message: detail)
                    }
                    if let reason = stopReason, reason != "end_turn" && reason != "stop_sequence" {
                        NSLog("Slicky early stop: %@ (chars=%d)", reason, totalChars)
                        // Don't throw on partial — caller decides whether to use the partial draft.
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - API key probe

    enum ProbeResult {
        case ok(model: String, sample: String)
        case unauthorized(message: String)
        case modelNotFound(message: String)
        case other(status: Int, message: String)
        case transport(Error)
    }

    /// Sends a tiny non-streaming request to verify (a) the API key is valid
    /// and (b) the model ID actually exists. Used by Settings → Test API Key.
    func probe(model: String, apiKey: String) async -> ProbeResult {
        do {
            var request = URLRequest(url: baseURL)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.timeoutInterval = 30

            let body = AnthropicRequest(
                model: model,
                messages: [.init(role: "user", content: "Reply with just the word: ok")],
                system: nil,
                maxTokens: 10,
                stream: false
            )
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let bodyString = String(data: data, encoding: .utf8) ?? "(non-utf8)"
            NSLog("Slicky probe %d: %@", status, bodyString)

            if status == 200 {
                struct R: Decodable {
                    let content: [Block]
                    struct Block: Decodable { let type: String; let text: String? }
                }
                let parsed = try JSONDecoder().decode(R.self, from: data)
                let text = parsed.content.compactMap { $0.text }.joined()
                return .ok(model: model, sample: text.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            let apiError = (try? JSONDecoder().decode(AnthropicError.self, from: data))
            let message = apiError?.error.message ?? bodyString
            switch status {
            case 401:
                return .unauthorized(message: message)
            case 404:
                return .modelNotFound(message: message)
            default:
                return .other(status: status, message: message)
            }
        } catch {
            return .transport(error)
        }
    }

    // MARK: - Non-streaming (for classify + critique)

    func complete(
        systemPrompt: String,
        userMessage: String,
        model: String,
        maxTokens: Int = 512,
        apiKey: String
    ) async throws -> String {
        var request = try buildRequest(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            model: model,
            maxTokens: maxTokens,
            apiKey: apiKey,
            stream: false
        )
        // Override stream in body
        let body = AnthropicRequest(
            model: model,
            messages: [.init(role: "user", content: userMessage)],
            system: systemPrompt.isEmpty ? nil : systemPrompt,
            maxTokens: maxTokens,
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "(non-utf8)"
            NSLog("Slicky Anthropic complete %d: %@", (response as? HTTPURLResponse)?.statusCode ?? -1, body)
            if let apiError = try? JSONDecoder().decode(AnthropicError.self, from: data) {
                throw apiError
            }
            throw URLError(.badServerResponse)
        }

        // Parse non-streaming response
        struct NonStreamResponse: Decodable {
            let content: [Block]
            struct Block: Decodable {
                let type: String
                let text: String?
            }
        }
        let result = try JSONDecoder().decode(NonStreamResponse.self, from: data)
        return result.content.compactMap { $0.text }.joined()
    }

    // MARK: - Request builder

    private func buildRequest(
        systemPrompt: String,
        userMessage: String,
        model: String,
        maxTokens: Int,
        apiKey: String,
        stream: Bool = true
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "accept")
        }
        request.timeoutInterval = 120

        let body = AnthropicRequest(
            model: model,
            messages: [.init(role: "user", content: userMessage)],
            system: systemPrompt.isEmpty ? nil : systemPrompt,
            maxTokens: maxTokens,
            stream: stream
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}
