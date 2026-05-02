import AppKit

final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem
    private let settings: SlickySettings
    private let openSettingsCallback: () -> Void
    private var hotkeyItem: NSMenuItem?
    private var messageItem: NSMenuItem?

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
        button.toolTip = "Slicky — Select text + \(settings.hotkeyDisplayString) to rewrite"
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
        statusItem.button?.toolTip = "Slicky — Select text + \(settings.hotkeyDisplayString) to rewrite"
    }

    @objc private func handleSettings() {
        openSettingsCallback()
    }

    func showMessage(_ message: String) {
        guard let button = statusItem.button else { return }
        let originalImage = button.image
        button.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)
        button.toolTip = message

        if let existing = messageItem {
            statusItem.menu?.removeItem(existing)
        }
        let item = NSMenuItem(title: "⚠ \(message)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        statusItem.menu?.insertItem(item, at: min(2, statusItem.menu?.items.count ?? 0))
        messageItem = item

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            button.image = originalImage
            self.refreshHotkey()
            if let item = self.messageItem {
                self.statusItem.menu?.removeItem(item)
                self.messageItem = nil
            }
        }
    }
}
