import AppKit
import SwiftUI
import Combine

enum PipelineStage: Equatable {
    case idle
    case classifying
    case drafting
    case critiquing
    case refining
    case done
    case failed(Error)

    static func == (lhs: PipelineStage, rhs: PipelineStage) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.classifying, .classifying), (.drafting, .drafting),
             (.critiquing, .critiquing), (.refining, .refining), (.done, .done):
            return true
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
}

@MainActor
final class HUDViewModel: ObservableObject {
    @Published var stage: PipelineStage = .idle
    @Published var classifiedIntent: Intent?
    @Published var draftText: String = ""
    @Published var critiqueScore: Int = 0
    @Published var critiqueIssues: [String] = []
    @Published var refinedText: String = ""
    @Published var finalText: String = ""
    @Published var isEditing: Bool = false
    @Published var editedText: String = ""

    private let rewriter = AgenticRewriter()
    private var rewriteTask: Task<Void, Never>?
    private var eventMonitor: Any?

    // MARK: - Start

    func startRewrite(context: CapturedContext, settings: SlickySettings) {
        guard !KeychainManager.shared.apiKey.isEmpty else { return }

        reset()
        stage = .classifying

        let apiKey = KeychainManager.shared.apiKey
        let stream = rewriter.rewrite(context: context, settings: settings, apiKey: apiKey)

        rewriteTask = Task {
            for await event in stream {
                handleEvent(event)
            }
        }
    }

    func cancel() {
        rewriteTask?.cancel()
        rewriteTask = nil
        stage = .idle
    }

    // MARK: - Event handling

    private func handleEvent(_ event: RewriteEvent) {
        switch event {
        case .classified(let intent):
            classifiedIntent = intent
            stage = .drafting

        case .draftToken(let token):
            draftText += token

        case .draftDone(let full):
            draftText = full
            stage = .critiquing
            editedText = full

        case .critique(let score, let issues, _):
            critiqueScore = score
            critiqueIssues = issues
            stage = .refining

        case .refineToken(let token):
            refinedText += token

        case .final(let text):
            finalText = text
            editedText = text
            stage = .done

        case .error(let err):
            stage = .failed(err)
        }
    }

    // MARK: - Keyboard monitor

    func installKeyMonitor(onAccept: @escaping () -> Void, onCancel: @escaping () -> Void) {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] (event: NSEvent) -> NSEvent? in
            guard let self = self else { return event }
            switch event.keyCode {
            case 36: // Return
                if !self.isEditing {
                    onAccept()
                    return nil
                }
                if event.modifierFlags.contains(.command) {
                    onAccept()
                    return nil
                }
            case 53: // Escape
                onCancel()
                return nil
            case 48: // Tab
                if !self.isEditing && self.stage == .done {
                    self.isEditing = true
                    return nil
                }
            default:
                break
            }
            return event
        }
    }

    func removeKeyMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Helpers

    var activeText: String {
        isEditing ? editedText : finalText
    }

    var isDone: Bool {
        if case .done = stage { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = stage { return true }
        return false
    }

    var errorMessage: String? {
        if case .failed(let err) = stage { return err.localizedDescription }
        return nil
    }

    private func reset() {
        stage = .idle
        classifiedIntent = nil
        draftText = ""
        critiqueScore = 0
        critiqueIssues = []
        refinedText = ""
        finalText = ""
        isEditing = false
        editedText = ""
    }
}
