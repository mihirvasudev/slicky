import SwiftUI
import AppKit
import ApplicationServices

struct SettingsView: View {
    @EnvironmentObject var settings: SlickySettings
    @State private var apiKeyInput: String = ""
    @State private var apiKeyMasked: Bool = true
    @State private var savedFlash: Bool = false
    @State private var axTrusted: Bool = false
    @State private var isRecordingHotkey: Bool = false
    @State private var hotkeyEventMonitor: Any?
    @State private var hotkeyStatusMessage: String?
    @State private var apiKeySaveError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                apiKeySection
                Divider()
                modelSection
                Divider()
                hotkeySection
                Divider()
                permissionsSection
                Divider()
                saveSection
            }
            .padding(24)
        }
        .frame(width: 480, height: 520)
        .onAppear {
            apiKeyInput = KeychainManager.shared.apiKey
            axTrusted = AXIsProcessTrusted()
        }
        .onChange(of: settings.draftModel) { _ in settings.persist() }
        .onChange(of: settings.classifyModel) { _ in settings.persist() }
        .onChange(of: settings.skipCritique) { _ in settings.persist() }
        .onChange(of: isRecordingHotkey) { recording in
            if recording {
                startHotkeyRecording()
            } else {
                stopHotkeyRecording()
            }
        }
        .onDisappear {
            stopHotkeyRecording()
        }
    }

    // MARK: - Sections

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("API Key", icon: "key.fill")

            HStack {
                if apiKeyMasked && !apiKeyInput.isEmpty {
                    SecureField("sk-ant-api03-...", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                } else {
                    TextField("sk-ant-api03-...", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                }
                Button(action: { apiKeyMasked.toggle() }) {
                    Image(systemName: apiKeyMasked ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 4) {
                Text("Get your key at")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Link("console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.caption)
            }

            if !apiKeyInput.isEmpty && apiKeySaveError == nil {
                Label(apiKeyInput == KeychainManager.shared.apiKey ? "Stored securely in macOS Keychain" : "Ready to save securely in macOS Keychain", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundColor(apiKeyInput == KeychainManager.shared.apiKey ? .green : .secondary)
            }

            if let apiKeySaveError {
                Label(apiKeySaveError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Model", icon: "cpu")

            VStack(spacing: 8) {
                HStack {
                    Text("Draft & Refine")
                        .frame(width: 140, alignment: .leading)
                    Picker("", selection: $settings.draftModel) {
                        ForEach(SlickySettings.DraftModel.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                HStack {
                    Text("Classify & Critique")
                        .frame(width: 140, alignment: .leading)
                    Picker("", selection: $settings.classifyModel) {
                        ForEach(SlickySettings.DraftModel.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                Toggle("Skip critique step (faster, ~60% cheaper)", isOn: $settings.skipCritique)
                    .help("Skips the self-critique and refinement step. Use for simple prompts when speed matters.")
            }
        }
    }

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Hotkey", icon: "keyboard")
            HStack {
                Text("Current hotkey")
                Spacer()
                Text(settings.hotkeyDisplayString)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlColor))
                    .cornerRadius(6)
            }

            HStack(spacing: 8) {
                Button(isRecordingHotkey ? "Press new shortcut..." : "Record Shortcut") {
                    hotkeyStatusMessage = isRecordingHotkey ? nil : "Press a key combo like ⌘⌥K. Esc cancels."
                    isRecordingHotkey.toggle()
                }
                .buttonStyle(.borderedProminent)

                Button("Reset") {
                    settings.resetHotkey()
                    (NSApp.delegate as? AppDelegate)?.reregisterHotkey()
                    hotkeyStatusMessage = "Reset to \(settings.hotkeyDisplayString)."
                }
                .buttonStyle(.bordered)
                .disabled(isRecordingHotkey)
            }

            Text(hotkeyStatusMessage ?? "Use at least Command, Option, or Control. Shift-only shortcuts are ignored so normal typing stays safe.")
                .font(.caption)
                .foregroundColor(isRecordingHotkey ? .accentColor : .secondary)
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Permissions", icon: "shield")
            HStack {
                Image(systemName: axTrusted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundColor(axTrusted ? .green : .orange)
                Text("Accessibility")
                Spacer()
                if !axTrusted {
                    Button("Grant Access") {
                        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                        AXIsProcessTrustedWithOptions(opts)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            axTrusted = AXIsProcessTrusted()
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var saveSection: some View {
        HStack {
            Button("Save") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(apiKeyInput.isEmpty && KeychainManager.shared.apiKey.isEmpty)

            if savedFlash {
                Label("Saved!", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
    }

    private func save() {
        apiKeySaveError = nil
        guard KeychainManager.shared.saveAPIKey(apiKeyInput) else {
            apiKeySaveError = "Could not save API key to Keychain. Check macOS Keychain access and try again."
            NSSound.beep()
            return
        }
        settings.persist()
        withAnimation { savedFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { savedFlash = false }
        }
    }

    private func startHotkeyRecording() {
        stopHotkeyRecording()
        hotkeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleHotkeyRecording(event)
        }
    }

    private func stopHotkeyRecording() {
        if let monitor = hotkeyEventMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyEventMonitor = nil
        }
    }

    private func handleHotkeyRecording(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 { // Escape
            hotkeyStatusMessage = "Recording cancelled."
            isRecordingHotkey = false
            return nil
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers.contains(.command) || modifiers.contains(.option) || modifiers.contains(.control) else {
            NSSound.beep()
            hotkeyStatusMessage = "Add Command, Option, or Control to avoid hijacking normal typing."
            return nil
        }

        guard let key = HotKeyCode(rawValue: UInt32(event.keyCode)) else {
            NSSound.beep()
            hotkeyStatusMessage = "That key is not supported yet. Try a letter, number, space, tab, or return."
            return nil
        }

        settings.setHotkey(key: key, modifiers: modifiers)
        (NSApp.delegate as? AppDelegate)?.reregisterHotkey()
        hotkeyStatusMessage = "Hotkey updated to \(settings.hotkeyDisplayString)."
        isRecordingHotkey = false
        return nil
    }
}
