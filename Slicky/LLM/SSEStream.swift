import Foundation

/// Anthropic stream errors surfaced to callers so the pipeline can show real
/// reasons (overloaded, content_filtered, max_tokens, refused) instead of
/// silently producing an empty draft.
struct AnthropicStreamError: LocalizedError {
    let kind: Kind
    let message: String

    enum Kind {
        case apiError           // explicit error event/payload
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
    case errorPayload(String)   // explicit error
    case ignore                 // unrelated event (ping, message_start, etc.)
}

/// Parses Server-Sent Events from Anthropic's Messages streaming API.
///
/// We dispatch based on the JSON payload's `"type"` field rather than the
/// SSE `event:` line. Reason: `URLSession.AsyncBytes.lines` chunking has
/// edge cases where the `event:` line gets coalesced or lost, leaving us
/// with just `data:` lines. Anthropic always includes a `"type"` in the
/// JSON itself, so this is the bulletproof source of truth.
struct SSEParser {
    private var currentData: String = ""
    private var currentEventType: String = ""

    mutating func processLine(_ line: String) -> SSEParseResult {
        if line.isEmpty {
            defer {
                currentData = ""
                currentEventType = ""
            }
            return dispatchEvent()
        }
        if line.hasPrefix("event:") {
            currentEventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            currentData = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        }
        // Some servers send multiple data: lines per event; we only honor the last.
        return .ignore
    }

    private func dispatchEvent() -> SSEParseResult {
        guard !currentData.isEmpty, currentData != "[DONE]" else { return .ignore }

        // Extract `"type"` from the JSON. Falls back to the SSE event: line
        // only if JSON parsing fails (which would be a server bug).
        let payloadType = extractType(from: currentData) ?? currentEventType

        switch payloadType {
        case "content_block_delta":
            if let text = extractTextDelta(from: currentData) {
                return .textDelta(text)
            }
            return .ignore
        case "message_delta":
            if let stop = extractStopReason(from: currentData) {
                return .stopReason(stop)
            }
            return .ignore
        case "error":
            return .errorPayload(extractErrorMessage(from: currentData) ?? currentData)
        case "ping", "message_start", "content_block_start", "content_block_stop", "message_stop", "":
            return .ignore
        default:
            // Unknown payload type — log it so we can debug, then ignore.
            NSLog("Slicky SSE unknown type: %@ data=%@", payloadType, String(currentData.prefix(200)))
            return .ignore
        }
    }

    // MARK: - JSON extractors

    private func extractType(from jsonString: String) -> String? {
        struct TypeOnly: Decodable { let type: String? }
        guard let data = jsonString.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(TypeOnly.self, from: data) else {
            return nil
        }
        return parsed.type
    }

    private func extractTextDelta(from jsonString: String) -> String? {
        struct DeltaWrap: Decodable {
            let delta: Delta
            struct Delta: Decodable {
                let type: String?
                let text: String?
            }
        }
        guard let data = jsonString.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(DeltaWrap.self, from: data) else {
            return nil
        }
        // Accept both text_delta and (defensive) any delta with a text field.
        // Skip thinking_delta — we don't want internal reasoning in the rewrite.
        if parsed.delta.type == "thinking_delta" { return nil }
        return parsed.delta.text
    }

    private func extractStopReason(from jsonString: String) -> String? {
        struct MessageDelta: Decodable {
            let delta: Inner
            struct Inner: Decodable {
                let stopReason: String?
                enum CodingKeys: String, CodingKey { case stopReason = "stop_reason" }
            }
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
