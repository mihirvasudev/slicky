import Foundation

final class IntentClassifier {
    private let client = AnthropicClient.shared

    private let systemPrompt = """
    You are a prompt intent classifier. Respond with EXACTLY ONE of these labels, nothing else:
    coding-feature
    coding-bug
    coding-refactor
    writing
    research
    general

    coding-feature: building new functionality, adding features, implementing something new
    coding-bug: fixing bugs, debugging, errors, crashes, unexpected behavior
    coding-refactor: restructuring, cleanup, optimization, migration, type changes
    writing: blog posts, emails, documentation, essays, messages, creative writing
    research: understanding concepts, explaining technology, comparing options
    general: anything that doesn't fit above
    """

    func classify(
        prompt: String,
        appBias: AppBias,
        apiKey: String,
        model: String
    ) async -> Intent {
        // Fast path: if we have a strong app bias signal, weight it heavily
        let biasHint: String
        switch appBias {
        case .coding:
            biasHint = "\n\nContext: The user is in a code editor or terminal. Strongly prefer coding-feature, coding-bug, or coding-refactor."
        case .writing:
            biasHint = "\n\nContext: The user is in a writing tool. Prefer writing."
        case .browser, .general:
            biasHint = ""
        }

        let userMessage = "Classify this prompt:\n\n\(prompt)\(biasHint)"

        do {
            let response = try await client.complete(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                model: model,
                maxTokens: 20,
                apiKey: apiKey
            )
            let label = response.trimmingCharacters(in: .whitespacesAndNewlines)
            return Intent(rawValue: label) ?? fallbackIntent(for: appBias)
        } catch {
            return fallbackIntent(for: appBias)
        }
    }

    private func fallbackIntent(for bias: AppBias) -> Intent {
        switch bias {
        case .coding: return .codingFeature
        case .writing: return .writing
        default: return .general
        }
    }
}
