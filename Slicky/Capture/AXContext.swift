import AppKit
import ApplicationServices

struct CapturedContext {
    let selectedText: String
    let surroundingText: String
    let appBundleID: String
    let appName: String
    let windowTitle: String
    let focusedElement: AXUIElement?
    let originalApp: NSRunningApplication?
}

final class AXContext {
    static let shared = AXContext()
    private init() {}

    func captureContext() throws -> CapturedContext {
        guard AXIsProcessTrusted() else {
            throw SlickyAXError.permissionDenied
        }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            throw SlickyAXError.noFrontApp
        }
        let pid = frontApp.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        // Get focused UI element
        var focusedRef: CFTypeRef?
        let focusedOK = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedRef).rawValue == 0
        let focusedElement: AXUIElement? = focusedOK ? (focusedRef as? AXUIElement) : nil

        // Try to get selected text from the focused element
        var selectedText = ""
        if let element = focusedElement {
            selectedText = readSelectedText(from: element)
        }

        // Fallback: clipboard trick for Electron/Terminal apps
        if selectedText.isEmpty {
            selectedText = ClipboardCapture.shared.captureSelection() ?? ""
        }

        // Surrounding text for context injection
        var surroundingText = ""
        if let element = focusedElement {
            surroundingText = readSurroundingText(from: element, selected: selectedText)
        }

        // Window title for file path hints
        var windowTitle = ""
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef).rawValue == 0,
           let window = windowRef as? AXUIElement {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef).rawValue == 0 {
                windowTitle = (titleRef as? String) ?? ""
            }
        }

        return CapturedContext(
            selectedText: selectedText,
            surroundingText: surroundingText,
            appBundleID: frontApp.bundleIdentifier ?? "",
            appName: frontApp.localizedName ?? "",
            windowTitle: windowTitle,
            focusedElement: focusedElement,
            originalApp: frontApp
        )
    }

    // MARK: - Private

    private func readSelectedText(from element: AXUIElement) -> String {
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &ref).rawValue == 0,
           let text = ref as? String, !text.isEmpty {
            return text
        }

        // Parameterized approach for apps that expose range but not direct text
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

    var errorDescription: String? {
        switch self {
        case .noFrontApp: return "No frontmost application found."
        case .permissionDenied: return "Accessibility permission not granted. Enable Slicky in System Settings › Privacy & Security › Accessibility."
        }
    }
}
