import AppKit

/// Orchestrates Slicky's capture strategies. The job is simple: produce a
/// `CapturedContext` no matter the user's settings, or fail loudly with a
/// message that tells them exactly what to do next.
///
/// `.smart` cascade (default):
///   1. AX selected text                — reliable in native apps
///   2. Fresh clipboard (<60s old)      — user just pressed ⌘C, trust them
///   3. Synthetic Cmd+C                 — try to capture fresh from front app
///   4. Recent clipboard (≤5min old)    — usable if synthetic also failed
///   5. Refuse stale clipboard          — fail with a clear "press ⌘C again" message
///
/// `.auto` is identical to `.smart` today (kept for backward-compat).
/// `.clipboardOnly` always uses whatever's on the clipboard, no synthetic event.
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()
    private init() {}

    /// Result of a `dryRun` capture — used by Settings → Test Capture so the
    /// user can verify their setup without going through the full pipeline.
    struct DiagnosticReport {
        let strategy: SlickySettings.CaptureStrategy
        let appName: String
        let bundleID: String
        let axTextPreview: String?
        let clipboardTextPreview: String?
        let clipboardAge: String
        let chosenSource: CaptureSource?
        let chosenTextPreview: String?
        let errorMessage: String?
    }

    func capture(strategy: SlickySettings.CaptureStrategy) throws -> CapturedContext {
        let ax = try AXContext.shared.readAccessibilityState()
        let clip = ClipboardReader.read()

        // 1. Native AX selection — instant, accurate, no clipboard touched.
        if strategy != .clipboardOnly, !ax.selectedText.isEmpty {
            return makeContext(ax: ax, text: ax.selectedText, surrounding: ax.surroundingText, source: .axSelection, clipAge: nil, warn: false)
        }

        // 2. Pure-Clipboard mode: trust whatever's there, no questions.
        if strategy == .clipboardOnly, let clip {
            return makeContext(ax: ax, text: clip.text, surrounding: "", source: .clipboardLive, clipAge: clip.ageDescription, warn: clip.isStale)
        }

        // 3. Smart/Auto: prefer fresh clipboard (the user just copied
        //    intentionally) — but never silently use stale clipboard,
        //    that's how we ended up rewriting the wrong text.
        if let clip, clip.isFresh {
            return makeContext(ax: ax, text: clip.text, surrounding: "", source: .clipboardLive, clipAge: clip.ageDescription, warn: false)
        }

        // 4. Try synthetic Cmd+C — even though it's brittle in Cursor, it's
        //    worth one shot because it almost always beats stale clipboard.
        if let synthetic = SyntheticCopy.shared.captureSelection(from: ax.originalApp), !synthetic.isEmpty {
            return makeContext(ax: ax, text: synthetic, surrounding: "", source: .syntheticCopy, clipAge: nil, warn: false)
        }

        // 5. Synthetic failed. We have two paths from here: there's stale
        //    clipboard text, or there's nothing.
        let appName = ax.appName.isEmpty ? "the current app" : ax.appName
        let detail = SyntheticCopy.shared.lastFailureReason

        if let clip {
            // Refuse to silently use stale clipboard. Tell the user the age
            // and what to do (press ⌘C again, or switch to clipboard-only).
            throw SlickyAXError.syntheticCopyFailedStaleClipboard(
                appName: appName,
                clipboardAge: clip.ageDescription,
                detail: detail
            )
        }

        throw SlickyAXError.noTextAnywhere(appName: appName, strategy: strategy, detail: detail)
    }

    /// Runs the AX + clipboard parts of the strategy without throwing or
    /// touching the clipboard — used by Settings → Test Capture so the user
    /// can verify what Slicky sees in any app. Synthetic copy is intentionally
    /// excluded because dryRun runs from Slicky's own window.
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
        } else if strategy == .clipboardOnly, let clip {
            chosenSource = .clipboardLive
            chosenText = clip.text
        } else if let clip, clip.isFresh {
            chosenSource = .clipboardLive
            chosenText = clip.text
        } else if clip != nil {
            errorMessage = "Clipboard has text from \(clip!.ageDescription), which is too old to use silently. With smart mode, Slicky would try ⌘C against \(appName) when you actually press the hotkey."
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

    private func makeContext(
        ax: AXContext.AXResult,
        text: String,
        surrounding: String,
        source: CaptureSource,
        clipAge: String?,
        warn: Bool
    ) -> CapturedContext {
        CapturedContext(
            selectedText: text,
            surroundingText: surrounding,
            appBundleID: ax.appBundleID,
            appName: ax.appName,
            windowTitle: ax.windowTitle,
            focusedElement: ax.focusedElement,
            originalApp: ax.originalApp,
            source: source,
            clipboardAgeDescription: clipAge,
            warnStaleClipboard: warn
        )
    }

    private static func preview(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 240 { return trimmed }
        return String(trimmed.prefix(240)) + "…"
    }
}
