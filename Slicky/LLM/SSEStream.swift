import Foundation

/// Parses Server-Sent Events from a line stream and extracts text deltas.
struct SSEParser {
    private var currentEventType: String = ""
    private var currentData: String = ""

    mutating func processLine(_ line: String) -> String? {
        if line.isEmpty {
            // Empty line = dispatch event
            defer {
                currentEventType = ""
                currentData = ""
            }
            return dispatchEvent()
        }

        if line.hasPrefix("event: ") {
            currentEventType = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data: ") {
            currentData = String(line.dropFirst(6))
        }
        return nil
    }

    private func dispatchEvent() -> String? {
        guard !currentData.isEmpty, currentData != "[DONE]" else { return nil }

        let eventType = SSEEventType(rawValue: currentEventType) ?? .contentBlockDelta

        switch eventType {
        case .contentBlockDelta:
            return extractTextDelta(from: currentData)
        default:
            return nil
        }
    }

    private func extractTextDelta(from jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        let delta = try? JSONDecoder().decode(ContentBlockDelta.self, from: data)
        guard delta?.delta.type == "text_delta" else { return nil }
        return delta?.delta.text
    }
}

/// Full SSE line-stream reader result
enum StreamLine {
    case token(String)
    case done
    case error(Error)
}
