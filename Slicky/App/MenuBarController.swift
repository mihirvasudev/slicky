import AppKit
import SwiftUI

final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem
    private let settings: SlickySettings
    private let openSettingsCallback: () -> Void
    private var hotkeyItem: NSMenuItem?
    private var messageItem: NSMenuItem?
    private var messagePopover: NSPopover?
    private var messageDismissWorkItem: DispatchWorkItem?

    init(settings: SlickySettings, openSettings: @escaping () -> Void) {
        self.settings = settings
        self.openSettingsCallback = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureButton()
        configureMenu()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Slicky")
        image?.isTemplate = true
        button.image = image
        button.toolTip = tooltipText()
    }

    private func tooltipText() -> String {
        "Slicky — Select text (or copy with ⌘C) + \(settings.hotkeyDisplayString) to rewrite"
    }

    private func configureMenu() {
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "Slicky", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        let hotkeyItem = NSMenuItem(title: "Hotkey: \(settings.hotkeyDisplayString)", action: nil, keyEquivalent: "")
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)
        self.hotkeyItem = hotkeyItem
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(handleSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Slicky", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func refreshHotkey() {
        hotkeyItem?.title = "Hotkey: \(settings.hotkeyDisplayString)"
        statusItem.button?.toolTip = tooltipText()
    }

    @objc private func handleSettings() {
        openSettingsCallback()
    }

    func showMessage(_ message: String) {
        guard let button = statusItem.button else { return }
        let originalImage = button.image
        button.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)
        button.toolTip = message
        NSLog("Slicky: %@", message)

        if let existing = messageItem {
            statusItem.menu?.removeItem(existing)
        }
        let item = NSMenuItem(title: "⚠ \(message)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        statusItem.menu?.insertItem(item, at: min(2, statusItem.menu?.items.count ?? 0))
        messageItem = item

        showMessagePopover(message, relativeTo: button)

        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            button.image = originalImage
            self.refreshHotkey()
            if let item = self.messageItem {
                self.statusItem.menu?.removeItem(item)
                self.messageItem = nil
            }
        }
    }

    private func showMessagePopover(_ message: String, relativeTo button: NSStatusBarButton) {
        messageDismissWorkItem?.cancel()
        messagePopover?.close()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 340, height: 180)
        popover.contentViewController = NSHostingController(rootView: SlickyMessagePopover(message: message))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        messagePopover = popover

        let dismiss = DispatchWorkItem { [weak self, weak popover] in
            popover?.close()
            if self?.messagePopover === popover {
                self?.messagePopover = nil
            }
        }
        messageDismissWorkItem = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: dismiss)
    }
}

private struct SlickyMessagePopover: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
                Text("Slicky could not continue")
                    .font(.headline)
            }

            Text(message)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Tip: in apps like Cursor, copy your text first with ⌘C, then press the Slicky hotkey.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("In Slicky Settings → Test Capture, you can verify what Slicky sees in any app.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
    }
}
