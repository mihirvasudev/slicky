import AppKit

/// Reads what's already on the clipboard. Pure read — no synthetic Cmd+C, no
/// app activation. This is the rock-solid Clippy-style path: when the user
/// presses Cmd+C themselves, *their* app handles the copy and we just read it.
struct ClipboardReader {
    /// Anything copied within this window counts as "fresh" — we trust the user
    /// just put it there intentionally and use it without trying synthetic copy.
    static let freshnessWindow: TimeInterval = 60

    struct Result {
        let text: String
        let ageSeconds: TimeInterval?
        let ageDescription: String

        var isFresh: Bool {
            guard let ageSeconds else { return false }
            return ageSeconds <= ClipboardReader.freshnessWindow
        }

        var isStale: Bool {
            guard let ageSeconds else { return false }
            return ageSeconds > 300
        }
    }

    static func read() -> Result? {
        let pasteboard = NSPasteboard.general
        guard let raw = pasteboard.string(forType: .string),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let age = ClipboardChangeTracker.shared.ageOfCurrentChange()
        let ageDescription = age.map { Self.formatAge($0) } ?? "unknown age"
        return Result(text: raw, ageSeconds: age, ageDescription: ageDescription)
    }

    static func formatAge(_ seconds: TimeInterval) -> String {
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(Int(seconds))s ago" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = Int(seconds / 3600)
        return "\(hours)h ago"
    }
}

/// Tracks the timestamp of the last NSPasteboard change so we can tell the
/// user whether they're rewriting freshly-copied text or something old.
final class ClipboardChangeTracker {
    static let shared = ClipboardChangeTracker()
    private init() { startWatching() }

    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var lastChangeAt: Date = Date()
    private var timer: Timer?

    private func startWatching() {
        // 0.5s is plenty fast for HUD purposes and costs ~nothing.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        let pb = NSPasteboard.general
        if pb.changeCount != lastChangeCount {
            lastChangeCount = pb.changeCount
            lastChangeAt = Date()
        }
    }

    /// Returns seconds since the clipboard last changed, or nil if we
    /// haven't observed a change yet (Slicky just launched).
    func ageOfCurrentChange() -> TimeInterval? {
        Date().timeIntervalSince(lastChangeAt)
    }
}

/// Synthetic copy: Slicky sends Cmd+C and reads the result. Brittle in
/// Electron apps. Only used when the user explicitly opts in to `.auto`.
final class SyntheticCopy {
    static let shared = SyntheticCopy()
    private init() {}

    private(set) var lastFailureReason: String = ""

    func captureSelection(from originalApp: NSRunningApplication?) -> String? {
        let pasteboard = NSPasteboard.general
        lastFailureReason = ""

        if let originalApp {
            originalApp.activate(options: .activateIgnoringOtherApps)
        }

        guard waitForAppToBecomeActive(originalApp, timeout: 1.0) else {
            lastFailureReason = "Couldn't return focus to \(originalApp?.localizedName ?? "the previous app") before sending the auto-copy."
            return nil
        }

        // AX menu copy is the most reliable mechanism in Electron apps. We
        // do NOT need modifiers to be released for this path because we're
        // dispatching a menu action, not synthesizing a keyboard event.
        let snapshot = PasteboardSnapshot(pasteboard)
        if let app = originalApp, tryCopy(via: { AXMenuCopy.performCopy(in: app) }, label: "AX Edit→Copy", pasteboard: pasteboard, snapshot: snapshot) {
            if let text = pasteboard.string(forType: .string), !text.isEmpty {
                let captured = text
                snapshot.restore(to: pasteboard)
                return captured
            }
        }

        // Synthetic keyboard events DO require modifiers to be released.
        guard waitForHotkeyModifiersToRelease(timeout: 1.2) else {
            lastFailureReason = "AX Edit→Copy didn't return text, and the hotkey modifiers are still held down so synthetic ⌘C would be misinterpreted. Release the hotkey faster after pressing it, or copy manually first."
            snapshot.restore(to: pasteboard)
            return nil
        }

        let kbAttempts: [(String, () -> Void)] = [
            ("CGEvent ⌘C", simulateCopy),
            ("System Events ⌘C", simulateCopyWithSystemEvents),
            ("CGEvent ⌘C retry", simulateCopy)
        ]
        for (label, copy) in kbAttempts {
            if tryCopy(via: { copy(); return true }, label: label, pasteboard: pasteboard, snapshot: snapshot) {
                if let text = pasteboard.string(forType: .string), !text.isEmpty {
                    let captured = text
                    snapshot.restore(to: pasteboard)
                    return captured
                }
            }
        }

        snapshot.restore(to: pasteboard)
        if lastFailureReason.isEmpty {
            lastFailureReason = "Tried AX Edit→Copy, CGEvent ⌘C, and System Events ⌘C — none of them changed the clipboard. The app may not have keyboard focus, or no text was selected."
        }
        return nil
    }

    /// Runs the given copy mechanism, snapshots/clears clipboard, and waits
    /// for the pasteboard to change. Returns true if the clipboard moved —
    /// caller is responsible for reading `pasteboard.string(forType:)`.
    private func tryCopy(via copy: () -> Bool, label: String, pasteboard: NSPasteboard, snapshot: PasteboardSnapshot) -> Bool {
        pasteboard.clearContents()
        let changeCountBefore = pasteboard.changeCount
        let dispatched = copy()
        if !dispatched {
            // The copy mechanism itself reported failure (e.g. no Edit menu).
            return false
        }
        let changed = waitForPasteboardChange(pasteboard, from: changeCountBefore, timeout: 1.2)
        if !changed {
            lastFailureReason = "\(label) didn't change the clipboard."
        }
        return changed
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

    private func simulateCopyWithSystemEvents() {
        let script = """
        tell application "System Events"
            keystroke "c" using command down
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            NSLog("Slicky System Events copy failed: %@", error)
        }
    }

    private func waitForAppToBecomeActive(_ app: NSRunningApplication?, timeout: TimeInterval) -> Bool {
        guard let app else { return true }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.isActive || NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                return true
            }
            app.activate(options: .activateIgnoringOtherApps)
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
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

// MARK: - PasteboardSnapshot

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
