import AppKit

/// Clipboard-based text capture for apps that don't expose AXSelectedText
/// (Terminal, iTerm2, some Electron apps).
final class ClipboardCapture {
    static let shared = ClipboardCapture()
    private init() {}

    /// Saves current clipboard, simulates Cmd+C to copy selection, reads result, restores clipboard.
    func captureSelection() -> String? {
        let pasteboard = NSPasteboard.general

        // Snapshot the entire pasteboard before touching it
        let snapshot = PasteboardSnapshot(pasteboard)
        let changeCountBefore = pasteboard.changeCount

        // Clear and send Cmd+C
        pasteboard.clearContents()
        simulateCopy()

        // Wait for the target app to write to the clipboard
        Thread.sleep(forTimeInterval: 0.12)

        let captured = pasteboard.string(forType: .string)
        let didChange = pasteboard.changeCount != changeCountBefore

        guard didChange, let text = captured, !text.isEmpty else {
            // Nothing new captured — restore immediately
            snapshot.restore(to: pasteboard)
            return nil
        }

        // Restore original clipboard after a short delay (so the target app
        // doesn't see a flash before it reads the paste event we're about to send)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            snapshot.restore(to: pasteboard)
        }

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
        guard !isEmpty else { return }
        pasteboard.clearContents()
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
