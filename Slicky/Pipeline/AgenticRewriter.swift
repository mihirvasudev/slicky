import Foundation

final class AgenticRewriter {
    private let client = AnthropicClient.shared
    private let classifier = IntentClassifier()

    // MARK: - Main pipeline

    func rewrite(
        context: CapturedContext,
        settings: SlickySettings,
        apiKey: String
    ) -> AsyncStream<RewriteEvent> {
        AsyncStream { continuation in
            Task {
                await self.runPipeline(
                    context: context,
                    settings: settings,
                    apiKey: apiKey,
                    continuation: continuation
                )
            }
        }
    }

    // MARK: - Pipeline steps

    private func runPipeline(
        context: CapturedContext,
        settings: SlickySettings,
        apiKey: String,
        continuation: AsyncStream<RewriteEvent>.Continuation
    ) async {
        let originalPrompt = context.selectedText

        // Step 1: Classify intent
        let appBias = AppDetector.bias(for: context.appBundleID, windowTitle: context.windowTitle)
        let intent = await classifier.classify(
            prompt: originalPrompt,
            appBias: appBias,
            apiKey: apiKey,
            model: settings.classifyModel.rawValue
        )
        continuation.yield(.classified(intent: intent))

        // Step 2: Draft
        let template = TemplateLoader.shared.load(intent: intent)
        let systemPrompt = TemplateLoader.shared.loadSystem()
        let contextHint = AppDetector.contextHint(for: context)

        let userMessage = template
            .replacingOccurrences(of: "{{ORIGINAL}}", with: originalPrompt)
            .replacingOccurrences(of: "{{APP}}", with: contextHint)
            .replacingOccurrences(of: "{{SURROUNDING}}", with: context.surroundingText)

        var draft = ""
        do {
            let stream = client.stream(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                model: settings.draftModel.rawValue,
                apiKey: apiKey
            )
            for try await token in stream {
                draft += token
                continuation.yield(.draftToken(token))
            }
        } catch {
            continuation.yield(.error(error))
            continuation.finish()
            return
        }

        // Hard bail when the draft is empty: critique-on-empty produces nonsense
        // ("Score 1/10, draft is empty") and refine can't fix nothing — better
        // to surface a real error so the user can edit and retry.
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            continuation.yield(.error(EmptyDraftError(originalPrompt: originalPrompt, model: settings.draftModel.displayName)))
            continuation.finish()
            return
        }

        continuation.yield(.draftDone(draft))

        // Step 3: Critique (optional)
        if settings.skipCritique {
            continuation.yield(.final(draft))
            continuation.finish()
            return
        }

        let critiqueResult = await runCritique(
            original: originalPrompt,
            draft: draft,
            intent: intent,
            apiKey: apiKey,
            model: settings.classifyModel.rawValue
        )
        continuation.yield(.critique(
            score: critiqueResult.score,
            issues: critiqueResult.issues,
            shouldRefine: critiqueResult.shouldRefine
        ))

        // Step 4: Refine if needed
        if critiqueResult.shouldRefine && !critiqueResult.issues.isEmpty {
            var refined = ""
            do {
                let refinePrompt = buildRefinePrompt(
                    original: originalPrompt,
                    draft: draft,
                    issues: critiqueResult.issues,
                    intent: intent
                )
                let stream = client.stream(
                    systemPrompt: systemPrompt,
                    userMessage: refinePrompt,
                    model: settings.draftModel.rawValue,
                    apiKey: apiKey
                )
                for try await token in stream {
                    refined += token
                    continuation.yield(.refineToken(token))
                }
                continuation.yield(.final(refined.isEmpty ? draft : refined))
            } catch {
                // Refine failed — use draft as final
                continuation.yield(.final(draft))
            }
        } else {
            continuation.yield(.final(draft))
        }

        continuation.finish()
    }

    // MARK: - Critique

    private struct CritiqueResult {
        let score: Int
        let issues: [String]
        let shouldRefine: Bool
    }

    private func runCritique(
        original: String,
        draft: String,
        intent: Intent,
        apiKey: String,
        model: String
    ) async -> CritiqueResult {
        let rubric = critqueRubric(for: intent)
        let critiquePrompt = """
        You are reviewing a rewritten prompt for quality. Evaluate the draft against the rubric and output JSON only.

        Original prompt: \(original)

        Rewritten draft:
        \(draft)

        Rubric:
        \(rubric)

        Output JSON with this exact shape:
        {"score": <0-10>, "issues": ["issue1", "issue2"], "shouldRefine": <true|false>}

        shouldRefine = true if score < 8 AND there are fixable issues.
        Keep issues array short (max 3 items). Be concise. JSON only, no other text.
        """

        do {
            let response = try await client.complete(
                systemPrompt: "",
                userMessage: critiquePrompt,
                model: model,
                maxTokens: 256,
                apiKey: apiKey
            )
            return parseCritique(response)
        } catch {
            return CritiqueResult(score: 8, issues: [], shouldRefine: false)
        }
    }

    private func parseCritique(_ json: String) -> CritiqueResult {
        struct CritiqueJSON: Decodable {
            let score: Int
            let issues: [String]
            let shouldRefine: Bool
        }
        // Extract JSON from response (model sometimes adds text around it)
        let text = json.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = text.firstIndex(of: "{") ?? text.startIndex
        let end = text.lastIndex(of: "}").map { text.index(after: $0) } ?? text.endIndex
        let jsonSubstring = String(text[start..<end])

        guard let data = jsonSubstring.data(using: .utf8),
              let result = try? JSONDecoder().decode(CritiqueJSON.self, from: data) else {
            return CritiqueResult(score: 8, issues: [], shouldRefine: false)
        }
        return CritiqueResult(score: result.score, issues: result.issues, shouldRefine: result.shouldRefine)
    }

    private func critqueRubric(for intent: Intent) -> String {
        switch intent {
        case .codingFeature, .codingRefactor:
            return """
            - Has a clear Goal (1 sentence, user-visible outcome)?
            - Has specific Acceptance Criteria (testable bullet points)?
            - Has Phased Execution with clean stopping points?
            - Has a Test Plan (edge cases, regression checks)?
            - Has Safety/Risk notes (what could break)?
            - Are file paths or module names mentioned where implied?
            - Is it concrete and imperative (not vague or hedging)?
            """
        case .codingBug:
            return """
            - Has reproduction steps?
            - Has root cause analysis request?
            - Has a fix plan?
            - Has regression test requirement?
            - Are error messages or symptoms quoted?
            """
        case .writing:
            return """
            - Specifies the audience?
            - Specifies the tone/style?
            - Specifies the desired structure or length?
            - Has a clear call-to-action or goal?
            """
        case .research:
            return """
            - Is the specific question clear?
            - Are comparison criteria specified (if comparing options)?
            - Is the output format requested (list, table, pros/cons)?
            """
        case .general:
            return """
            - Is the goal clear?
            - Are constraints mentioned?
            - Is the desired output format specified?
            """
        }
    }

    // MARK: - Refine prompt

    private func buildRefinePrompt(
        original: String,
        draft: String,
        issues: [String],
        intent: Intent
    ) -> String {
        let issueList = issues.map { "- \($0)" }.joined(separator: "\n")
        return """
        You are refining a rewritten prompt. Fix ONLY the listed issues. Keep everything else identical.
        Output ONLY the improved prompt, no preamble.

        Original user prompt: \(original)

        Current draft:
        \(draft)

        Issues to fix:
        \(issueList)

        Intent: \(intent.displayName)
        """
    }
}

// MARK: - Errors

struct EmptyDraftError: LocalizedError {
    let originalPrompt: String
    let model: String

    var errorDescription: String? {
        let preview = originalPrompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)
        let snippet = preview.isEmpty ? "" : " (you sent: \"\(preview)…\")"
        return "\(model) returned no text\(snippet). This usually means the input wasn't a prompt to rewrite (e.g. shell commands, code-only blocks, or content the model declined). Edit the original and try again, or pick a different model in Settings."
    }
}

// MARK: - Template Loader

final class TemplateLoader {
    static let shared = TemplateLoader()
    private init() {}

    func load(intent: Intent) -> String {
        let name = intent.templateName
        return loadFile(named: name) ?? fallbackTemplate(for: intent)
    }

    func loadSystem() -> String {
        return loadFile(named: "system") ?? "You are an expert prompt engineer. Output only the rewritten prompt, no preamble."
    }

    private func loadFile(named name: String) -> String? {
        // Primary: folder reference copies Templates/ into bundle root
        if let base = Bundle.main.resourceURL {
            let url = base.appendingPathComponent("Templates/\(name).md")
            if let content = try? String(contentsOf: url, encoding: .utf8) { return content }
        }
        // Secondary: individual resource (if bundled without folder reference)
        for subdir in ["Templates", nil as String?] {
            if let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: subdir),
               let content = try? String(contentsOf: url, encoding: .utf8) {
                return content
            }
        }
        // Development fallback: walk up from bundle to find source tree
        let devPath = URL(fileURLWithPath: Bundle.main.bundlePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Slicky/Resources/Templates/\(name).md")
        return try? String(contentsOf: devPath, encoding: .utf8)
    }

    private func fallbackTemplate(for intent: Intent) -> String {
        """
        Rewrite this \(intent.displayName) prompt to be specific, actionable, and well-structured.
        Output only the rewritten prompt.

        Original: <<<{{ORIGINAL}}>>>
        Context: {{APP}}
        """
    }
}
