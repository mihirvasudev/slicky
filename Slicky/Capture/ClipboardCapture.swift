import AppKit

/// Clipboard-based text capture for apps that don't expose AXSelectedText
/// (Terminal, iTerm2, some Electron apps).
final class ClipboardCapture {
    static let shared = ClipboardCapture()
    private init() {}

    private(set) var lastFailureReason: String = ""

    /// Saves current clipboard, simulates Cmd+C to copy selection, reads result, restores clipboard.
    func captureSelection(from originalApp: NSRunningApplication?) -> String? {
        let pasteboard = NSPasteboard.general
        lastFailureReason = ""

        if let originalApp {
            originalApp.activate(options: .activateIgnoringOtherApps)
        }

        guard waitForHotkeyModifiersToRelease(timeout: 1.2) else {
            lastFailureReason = "The hotkey modifiers were still held down, so Cursor may not receive a plain Cmd+C copy command. Release the hotkey keys quickly after pressing it."
            return nil
        }

        // Snapshot the entire pasteboard before touching it
        let snapshot = PasteboardSnapshot(pasteboard)

        // Clear and send Cmd+C
        pasteboard.clearContents()
        let changeCountBefore = pasteboard.changeCount
        simulateCopy()

        guard waitForPasteboardChange(pasteboard, from: changeCountBefore, timeout: 0.8) else {
            snapshot.restore(to: pasteboard)
            lastFailureReason = "Clipboard fallback sent Cmd+C, but the clipboard did not change. The active app may have blocked copy, or no text was selected."
            return nil
        }

        let captured = pasteboard.string(forType: .string)

        guard let text = captured, !text.isEmpty else {
            // Nothing new captured — restore immediately
            snapshot.restore(to: pasteboard)
            lastFailureReason = "Clipboard changed, but it did not contain plain text."
            return nil
        }

        snapshot.restore(to: pasteboard)

        return text
    }

    private func simulateCopy() {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: true) // 8 = C
        down?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cgSessionEventTap)
    }

    private func waitForHotkeyModifiersToRelease(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let modifiersStillDown = flags.contains(.maskCommand)
                || flags.contains(.maskAlternate)
                || flags.contains(.maskControl)
                || flags.contains(.maskShift)
            if !modifiersStillDown {
                return true
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return false
    }

    private func waitForPasteboardChange(_ pasteboard: NSPasteboard, from changeCount: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pasteboard.changeCount != changeCount {
                return true
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return false
    }
}

// MARK: - TextInjector clipboard helper (shared by TextInjector)

/// Saves and restores all items on a pasteboard — preserves rich text, images, files, etc.
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var types: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    types[type] = data
                }
            }
            return types
        }
    }

    var isEmpty: Bool { items.isEmpty }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !isEmpty else { return }
        let newItems = items.map { typeMap -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in typeMap {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(newItems)
    }
}
