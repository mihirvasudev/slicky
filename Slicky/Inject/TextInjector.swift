import AppKit

final class TextInjector {
    static let shared = TextInjector()
    private init() {}

    /// Injects text into the target element, using AX if possible, clipboard+Cmd+V as fallback.
    func inject(text: String, context: CapturedContext, completion: @escaping () -> Void) {
        // Try AX first — works without activating the original app
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
        // Replace selected text
        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return result == .success
    }

    // MARK: - Clipboard Injection

    private func injectViaClipboard(text: String, originalApp: NSRunningApplication?, completion: @escaping () -> Void) {
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Activate the original app, then send Cmd+V
        if let app = originalApp {
            app.activate(options: .activateIgnoringOtherApps)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.simulatePaste()
            completion()

            // Restore clipboard after paste has time to process
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let prev = previousContent {
                    pasteboard.clearContents()
                    pasteboard.setString(prev, forType: .string)
                }
            }
        }
    }

    private func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true) // 9 = V
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)

        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
