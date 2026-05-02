import AppKit

final class TextInjector {
    static let shared = TextInjector()
    private init() {}

    /// Injects text into the target element, using AX if possible, clipboard+Cmd+V as fallback.
    func inject(text: String, context: CapturedContext, completion: @escaping () -> Void) {
        // Try AX first — works without activating the original app or touching clipboard
        if let element = context.focusedElement, injectViaAX(text: text, into: element) {
            completion()
            return
        }
        // Fallback: clipboard + Cmd+V
        injectViaClipboard(text: text, originalApp: context.originalApp, completion: completion)
    }

    // MARK: - AX Injection

    @discardableResult
    private func injectViaAX(text: String, into element: AXUIElement) -> Bool {
        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return result == .success
    }

    // MARK: - Clipboard Injection

    private func injectViaClipboard(
        text: String,
        originalApp: NSRunningApplication?,
        completion: @escaping () -> Void
    ) {
        let pasteboard = NSPasteboard.general

        // Snapshot entire clipboard (images, files, rich text — everything)
        let snapshot = PasteboardSnapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Re-activate the original app then send Cmd+V
        if let app = originalApp {
            app.activate(options: .activateIgnoringOtherApps)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.simulatePaste()
            completion()

            // Restore original clipboard contents after the paste has landed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                snapshot.restore(to: pasteboard)
            }
        }
    }

    private func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true) // 9 = V
        down?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cgSessionEventTap)
    }
}
