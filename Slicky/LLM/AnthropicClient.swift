import Foundation

final class AnthropicClient {
    static let shared = AnthropicClient()
    private init() {}

    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"

    // MARK: - Streaming

    /// Streams text tokens from the Anthropic Messages API.
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
                        if let data = body.data(using: .utf8),
                           let apiError = try? JSONDecoder().decode(AnthropicError.self, from: data) {
                            throw apiError
                        }
                        throw URLError(.badServerResponse)
                    }

                    var parser = SSEParser()
                    for try await line in bytes.lines {
                        if let token = parser.processLine(line) {
                            continuation.yield(token)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
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
