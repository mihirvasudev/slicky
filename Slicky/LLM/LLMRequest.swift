import Foundation

// MARK: - Request

struct AnthropicRequest: Encodable {
    let model: String
    let messages: [Message]
    let system: String?
    let maxTokens: Int
    let stream: Bool

    struct Message: Encodable {
        let role: String
        let content: String
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, system
        case maxTokens = "max_tokens"
        case stream
    }
}

// MARK: - SSE Event types

enum SSEEventType: String {
    case messageStart = "message_start"
    case contentBlockStart = "content_block_start"
    case contentBlockDelta = "content_block_delta"
    case contentBlockStop = "content_block_stop"
    case messageDelta = "message_delta"
    case messageStop = "message_stop"
    case ping
    case error
}

struct ContentBlockDelta: Decodable {
    let index: Int
    let delta: Delta

    struct Delta: Decodable {
        let type: String
        let text: String?
        let thinkingText: String?

        enum CodingKeys: String, CodingKey {
            case type, text
            case thinkingText = "thinking"
        }
    }
}

// MARK: - Error response

struct AnthropicError: Decodable, LocalizedError {
    let type: String
    let error: ErrorBody

    struct ErrorBody: Decodable {
        let type: String
        let message: String
    }

    var errorDescription: String? {
        "Anthropic API error (\(error.type)): \(error.message)"
    }
}
