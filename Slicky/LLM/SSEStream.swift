import Foundation

/// Anthropic stream errors surfaced to callers so the pipeline can show real
/// reasons (overloaded, content_filtered, max_tokens, refused) instead of
/// silently producing an empty draft.
struct AnthropicStreamError: LocalizedError {
    let kind: Kind
    let message: String

    enum Kind {
        case apiError           // event: error with a payload
        case truncated          // stop_reason indicating an incomplete response
        case noContent          // model returned no content tokens at all
        case parserFailure      // SSE parser couldn't decode the payload
    }

    var errorDescription: String? {
        switch kind {
        case .apiError:
            return "Anthropic API error: \(message)"
        case .truncated:
            return "Anthropic stopped early: \(message)"
        case .noContent:
            return "Anthropic returned no content. \(message)"
        case .parserFailure:
            return "Could not parse the streaming response: \(message)"
        }
    }
}

/// Output of a single parsed SSE event.
enum SSEParseResult {
    case textDelta(String)      // a piece of model-generated text
    case stopReason(String)     // message_delta with stop_reason
    case errorPayload(String)   // event: error
    case ignore                 // unrelated event (ping, message_start, etc.)
}

/// Parses Server-Sent Events from Anthropic's Messages streaming API.
///
/// Critically, this version does NOT default unknown events to
/// `content_block_delta` — that swallowed real `error` events and
/// stop_reasons silently in the past, producing empty drafts.
struct SSEParser {
    private var currentEventType: String = ""
    private var currentData: String = ""

    mutating func processLine(_ line: String) -> SSEParseResult {
        if line.isEmpty {
            defer {
                currentEventType = ""
                currentData = ""
            }
            return dispatchEvent()
        }
        if line.hasPrefix("event:") {
            currentEventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            currentData = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        }
        return .ignore
    }

    private func dispatchEvent() -> SSEParseResult {
        guard !currentData.isEmpty, currentData != "[DONE]" else { return .ignore }
        let kind = SSEEventType(rawValue: currentEventType)
        switch kind {
        case .contentBlockDelta:
            if let text = extractTextDelta(from: currentData) {
                return .textDelta(text)
            }
            return .ignore
        case .messageDelta:
            if let stop = extractStopReason(from: currentData) {
                return .stopReason(stop)
            }
            return .ignore
        case .error:
            let extracted = extractErrorMessage(from: currentData) ?? currentData
            return .errorPayload(extracted)
        case .messageStart, .contentBlockStart, .contentBlockStop, .messageStop, .ping, .none:
            return .ignore
        }
    }

    private func extractTextDelta(from jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        let delta = try? JSONDecoder().decode(ContentBlockDelta.self, from: data)
        guard delta?.delta.type == "text_delta" else { return nil }
        return delta?.delta.text
    }

    private func extractStopReason(from jsonString: String) -> String? {
        struct MessageDelta: Decodable {
            struct Inner: Decodable { let stopReason: String?; enum CodingKeys: String, CodingKey { case stopReason = "stop_reason" } }
            let delta: Inner
        }
        guard let data = jsonString.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(MessageDelta.self, from: data) else {
            return nil
        }
        return parsed.delta.stopReason
    }

    private func extractErrorMessage(from jsonString: String) -> String? {
        struct StreamError: Decodable {
            let error: Inner?
            struct Inner: Decodable {
                let type: String?
                let message: String?
            }
        }
        guard let data = jsonString.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(StreamError.self, from: data) else {
            return nil
        }
        if let inner = parsed.error {
            return [inner.type, inner.message].compactMap { $0 }.joined(separator: ": ")
        }
        return nil
    }
}
