import AppKit

/// Clipboard-based text capture for apps that don't expose AXSelectedText
/// (Terminal, iTerm2, some Electron apps).
final class ClipboardCapture {
    static let shared = ClipboardCapture()
    private init() {}

    /// Saves current clipboard, simulates Cmd+C to copy selection, reads result, restores clipboard.
    func captureSelection() -> String? {
        let pasteboard = NSPasteboard.general

        // Save existing clipboard contents
        let savedContents = pasteboard.string(forType: .string)
        let savedChangeCount = pasteboard.changeCount

        // Clear and send Cmd+C
        pasteboard.clearContents()
        simulateCopy()

        // Wait briefly for clipboard to update
        Thread.sleep(forTimeInterval: 0.12)

        let captured = pasteboard.string(forType: .string)
        let changed = pasteboard.changeCount != savedChangeCount

        // Restore original clipboard if we got nothing or same content
        if !changed || captured == nil {
            if let saved = savedContents {
                pasteboard.clearContents()
                pasteboard.setString(saved, forType: .string)
            }
            return nil
        }

        // Restore original after a short delay so apps don't see a flash
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let saved = savedContents {
                pasteboard.clearContents()
                pasteboard.setString(saved, forType: .string)
            }
        }

        return captured
    }

    private func simulateCopy() {
        let src = CGEventSource(stateID: .hidSystemState)

        // Key down C with Command
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: true) // 8 = C
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)

        // Key up C
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
