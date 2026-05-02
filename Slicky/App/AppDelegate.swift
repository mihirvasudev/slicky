import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SlickySettings()
    var menuBarController: MenuBarController?
    var hotkeyManager: HotkeyManager?
    var hudController: HUDWindowController?
    var onboardingWindow: NSWindow?  // strong ref prevents dealloc

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        menuBarController = MenuBarController(settings: settings, openSettings: openSettings)
        hudController = HUDWindowController(settings: settings)
        hotkeyManager = HotkeyManager()

        // Start clipboard change tracker early so we can show useful "copied 12s ago"
        // age information in diagnostics and the HUD.
        _ = ClipboardChangeTracker.shared

        registerHotkey()
        requestAccessibilityIfNeeded()

        if !settings.onboardingComplete {
            showOnboarding()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Hotkey

    private func registerHotkey() {
        hotkeyManager?.register(key: settings.hotkeyKey, modifiers: settings.hotkeyModifiers) { [weak self] in
            // hotkeyFired() is @MainActor; the HotKey callback is not, so hop to the main queue.
            DispatchQueue.main.async { self?.hotkeyFired() }
        }
    }

    func reregisterHotkey() {
        hotkeyManager?.unregister()
        registerHotkey()
        menuBarController?.refreshHotkey()
    }

    @MainActor
    func hotkeyFired() {
        guard settings.onboardingComplete else {
            showOnboarding()
            return
        }
        guard !KeychainManager.shared.apiKey.isEmpty else {
            menuBarController?.showMessage("Add your Anthropic API key in Settings first.")
            openSettings()
            return
        }
        guard AXIsProcessTrusted() else {
            menuBarController?.showMessage("Grant Accessibility permission in Settings first.")
            requestAccessibilityIfNeeded()
            return
        }
        guard let hud = hudController, !hud.isVisible else { return }

        // Auto strategy synthesises Cmd+C and needs the modifiers released first
        // so the target app sees a clean ⌘C. Other strategies fire immediately.
        if settings.captureStrategy == .auto {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.captureAndShowHUD()
            }
        } else {
            captureAndShowHUD()
        }
    }

    @MainActor
    private func captureAndShowHUD() {
        guard let hud = hudController, !hud.isVisible else { return }

        do {
            let context = try CaptureCoordinator.shared.capture(strategy: settings.captureStrategy)
            hud.show(context: context)
        } catch {
            menuBarController?.showMessage(error.localizedDescription)
        }
    }

    // MARK: - Permissions

    func requestAccessibilityIfNeeded() {
        if !AXIsProcessTrusted() {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    // MARK: - Windows

    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        // macOS 13+ uses showSettingsWindow:, macOS 12 uses showPreferencesWindow:
        if #available(macOS 13, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    func showOnboarding() {
        // Guard against showing twice
        if let existing = onboardingWindow, existing.isVisible { existing.makeKeyAndOrderFront(nil); return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Slicky"
        window.center()
        window.contentView = NSHostingView(
            rootView: OnboardingView(settings: settings) { [weak self, weak window] in
                self?.settings.onboardingComplete = true
                window?.orderOut(nil)
                self?.onboardingWindow = nil
                self?.requestAccessibilityIfNeeded()
            }
        )
        onboardingWindow = window   // retain strongly so ARC doesn't deallocate it
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
