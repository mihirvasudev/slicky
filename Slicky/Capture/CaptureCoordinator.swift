import AppKit

/// Orchestrates Slicky's capture strategies. The job is simple: produce a
/// `CapturedContext` no matter the user's settings, or fail loudly with a
/// message that tells them exactly what to do next.
///
/// Strategy order:
/// - `.smart`         AX selection → existing clipboard
/// - `.auto`          AX selection → existing clipboard → synthetic Cmd+C
/// - `.clipboardOnly` Existing clipboard only (fastest, never reads AX text)
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()
    private init() {}

    /// Result of a `dryRun` capture — used by Settings → Test Capture so the
    /// user can verify their setup without going through the full pipeline.
    struct DiagnosticReport {
        let strategy: SlickySettings.CaptureStrategy
        let appName: String
        let bundleID: String
        let axTextPreview: String?     // nil if AX returned nothing
        let clipboardTextPreview: String?
        let clipboardAge: String
        let chosenSource: CaptureSource?
        let chosenTextPreview: String?
        let errorMessage: String?
    }

    func capture(strategy: SlickySettings.CaptureStrategy) throws -> CapturedContext {
        let ax = try AXContext.shared.readAccessibilityState()

        // Strategy 1: native AX selection (only mode that doesn't depend on the user)
        if strategy != .clipboardOnly, !ax.selectedText.isEmpty {
            return makeContext(ax: ax, text: ax.selectedText, surrounding: ax.surroundingText, source: .axSelection)
        }

        // Strategy 2: read whatever the user already put on the clipboard.
        if let clip = ClipboardReader.read() {
            return makeContext(ax: ax, text: clip.text, surrounding: "", source: .clipboardLive)
        }

        // Strategy 3 (only `.auto`): synthetic Cmd+C as a last resort.
        if strategy == .auto, let synthetic = SyntheticCopy.shared.captureSelection(from: ax.originalApp) {
            return makeContext(ax: ax, text: synthetic, surrounding: "", source: .syntheticCopy)
        }

        let detail = strategy == .auto ? SyntheticCopy.shared.lastFailureReason : ""
        throw SlickyAXError.noTextAnywhere(
            appName: ax.appName.isEmpty ? "the current app" : ax.appName,
            strategy: strategy,
            detail: detail
        )
    }

    /// Runs the AX + clipboard parts of the strategy without throwing or
    /// touching the clipboard — used by Settings → Test Capture so the user
    /// can verify what Slicky sees in any app. Synthetic copy is intentionally
    /// excluded because dryRun runs from Slicky's own window: simulating
    /// Cmd+C against Slicky would mess with the user's clipboard for nothing.
    func dryRun(strategy: SlickySettings.CaptureStrategy) -> DiagnosticReport {
        let axState: AXContext.AXResult? = (try? AXContext.shared.readAccessibilityState())
        let appName = axState?.appName ?? "(unknown — Accessibility not granted?)"
        let bundleID = axState?.appBundleID ?? ""
        let axText: String? = (axState?.selectedText.isEmpty ?? true) ? nil : axState?.selectedText
        let clip = ClipboardReader.read()

        var chosenSource: CaptureSource?
        var chosenText: String?
        var errorMessage: String?

        if axState == nil {
            errorMessage = "Accessibility permission is missing — open System Settings → Privacy & Security → Accessibility and toggle Slicky on."
        } else if strategy != .clipboardOnly, let axText {
            chosenSource = .axSelection
            chosenText = axText
        } else if let clip {
            chosenSource = .clipboardLive
            chosenText = clip.text
        } else if strategy == .auto {
            errorMessage = "Nothing visible to read. With Auto-copy fallback, Slicky would press ⌘C against \(appName) — try the actual hotkey to test that."
        } else {
            errorMessage = "Nothing on the clipboard, and \(appName) didn't expose selected text."
        }

        return DiagnosticReport(
            strategy: strategy,
            appName: appName,
            bundleID: bundleID,
            axTextPreview: axText.map(Self.preview),
            clipboardTextPreview: clip?.text.isEmpty == false ? Self.preview(clip!.text) : nil,
            clipboardAge: clip?.ageDescription ?? "—",
            chosenSource: chosenSource,
            chosenTextPreview: chosenText.map(Self.preview),
            errorMessage: errorMessage
        )
    }

    // MARK: - Helpers

    private func makeContext(ax: AXContext.AXResult, text: String, surrounding: String, source: CaptureSource) -> CapturedContext {
        CapturedContext(
            selectedText: text,
            surroundingText: surrounding,
            appBundleID: ax.appBundleID,
            appName: ax.appName,
            windowTitle: ax.windowTitle,
            focusedElement: ax.focusedElement,
            originalApp: ax.originalApp,
            source: source
        )
    }

    private static func preview(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 240 { return trimmed }
        return String(trimmed.prefix(240)) + "…"
    }
}
