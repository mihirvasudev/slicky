import AppKit
import ApplicationServices

/// Where the captured text came from. Surfaced in the HUD so the user knows
/// whether Slicky read the live selection, used what they pre-copied, or
/// resorted to the synthetic Cmd+C path.
enum CaptureSource: String {
    case axSelection      // Read directly from AXSelectedText / parameterized AX.
    case clipboardLive    // Existing clipboard contents (Clippy-style).
    case syntheticCopy    // Slicky pressed Cmd+C and read the result.
}

struct CapturedContext {
    let selectedText: String
    let surroundingText: String
    let appBundleID: String
    let appName: String
    let windowTitle: String
    let focusedElement: AXUIElement?
    let originalApp: NSRunningApplication?
    let source: CaptureSource
    /// Only populated when `source == .clipboardLive`; "12s ago", "5m ago", etc.
    let clipboardAgeDescription: String?
    /// True when we used clipboard text that hadn't been updated recently and
    /// synthetic copy *also* failed. The HUD warns the user prominently.
    let warnStaleClipboard: Bool

    /// Convenience: the live AX selection always represents the *current*
    /// cursor selection, while the clipboard might be older. Useful for HUD copy.
    var sourceDisplay: String {
        switch source {
        case .axSelection:    return "from selection"
        case .clipboardLive:
            if let age = clipboardAgeDescription { return "from clipboard · \(age)" }
            return "from clipboard"
        case .syntheticCopy:  return "auto-copied"
        }
    }
}

/// AXContext now owns *only* the Accessibility-tree reading. Coordination
/// across strategies (AX → clipboard → synthetic) lives in CaptureCoordinator.
final class AXContext {
    static let shared = AXContext()
    private init() {}

    struct AXResult {
        let selectedText: String
        let surroundingText: String
        let focusedElement: AXUIElement?
        let appBundleID: String
        let appName: String
        let windowTitle: String
        let originalApp: NSRunningApplication?
    }

    /// Reads selected/surrounding text + window context purely via Accessibility.
    /// Returns empty `selectedText` when AX has nothing to offer (Cursor, etc.) —
    /// the coordinator decides what to do next.
    func readAccessibilityState() throws -> AXResult {
        guard AXIsProcessTrusted() else {
            throw SlickyAXError.permissionDenied
        }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            throw SlickyAXError.noFrontApp
        }
        let pid = frontApp.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        var focusedRef: CFTypeRef?
        let focusedOK = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedRef).rawValue == 0
        let focusedElement: AXUIElement? = focusedOK ? axElement(from: focusedRef) : nil

        var selectedText = ""
        if let element = focusedElement {
            selectedText = readSelectedText(from: element)
        }

        var surroundingText = ""
        if let element = focusedElement, !selectedText.isEmpty {
            surroundingText = readSurroundingText(from: element, selected: selectedText)
        }

        var windowTitle = ""
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef).rawValue == 0,
           let window = axElement(from: windowRef) {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef).rawValue == 0 {
                windowTitle = (titleRef as? String) ?? ""
            }
        }

        return AXResult(
            selectedText: selectedText,
            surroundingText: surroundingText,
            focusedElement: focusedElement,
            appBundleID: frontApp.bundleIdentifier ?? "",
            appName: frontApp.localizedName ?? "",
            windowTitle: windowTitle,
            originalApp: frontApp
        )
    }

    // MARK: - Private

    private func axElement(from value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func readSelectedText(from element: AXUIElement) -> String {
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &ref).rawValue == 0,
           let text = ref as? String, !text.isEmpty {
            return text
        }

        // Parameterized approach for apps that expose range but not direct text.
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef).rawValue == 0,
           let rangeValue = rangeRef {
            var stringRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXStringForRangeParameterizedAttribute as CFString,
                rangeValue,
                &stringRef
            ).rawValue == 0, let text = stringRef as? String, !text.isEmpty {
                return text
            }
        }

        return ""
    }

    private func readSurroundingText(from element: AXUIElement, selected: String) -> String {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &ref).rawValue == 0,
              let fullText = ref as? String else { return "" }

        let maxLen = 500
        if fullText.count <= maxLen { return fullText }

        guard !selected.isEmpty, let range = fullText.range(of: selected) else {
            return String(fullText.prefix(maxLen))
        }
        let selectionStart = fullText.distance(from: fullText.startIndex, to: range.lowerBound)
        let contextStart = max(0, selectionStart - 200)
        let startIndex = fullText.index(fullText.startIndex, offsetBy: contextStart)
        let available = fullText.count - contextStart
        let endIndex = fullText.index(startIndex, offsetBy: min(maxLen, available))
        return String(fullText[startIndex..<endIndex])
    }
}

// MARK: - Errors

enum SlickyAXError: LocalizedError {
    case noFrontApp
    case permissionDenied
    case noTextAnywhere(appName: String, strategy: SlickySettings.CaptureStrategy, detail: String)
    case syntheticCopyFailedStaleClipboard(appName: String, clipboardAge: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .noFrontApp:
            return "No frontmost application found."
        case .permissionDenied:
            return "Accessibility permission not granted. Enable Slicky in System Settings › Privacy & Security › Accessibility."
        case .noTextAnywhere(let appName, let strategy, let detail):
            switch strategy {
            case .smart, .auto:
                let base = "Slicky couldn't read selected text from \(appName), and there's nothing on your clipboard. Copy your prompt first (⌘C), then press the Slicky hotkey."
                return detail.isEmpty ? base : "\(base) \(detail)"
            case .clipboardOnly:
                return "Your clipboard doesn't have any plain text. Copy your prompt first (⌘C), then press the Slicky hotkey."
            }
        case .syntheticCopyFailedStaleClipboard(let appName, let clipboardAge, let detail):
            // We refuse to silently rewrite stale clipboard text — the user
            // almost certainly meant their current selection.
            let base = "Slicky couldn't read your selection in \(appName). Your clipboard text is from \(clipboardAge) — too old to assume you meant it. Copy your prompt freshly (⌘C), then press the Slicky hotkey again."
            return detail.isEmpty ? base : "\(base) \(detail)"
        }
    }
}
