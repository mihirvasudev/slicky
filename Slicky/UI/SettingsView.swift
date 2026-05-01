import SwiftUI
import ApplicationServices

struct SettingsView: View {
    @EnvironmentObject var settings: SlickySettings
    @State private var apiKeyInput: String = ""
    @State private var apiKeyMasked: Bool = true
    @State private var savedFlash: Bool = false
    @State private var axTrusted: Bool = false

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

            if !apiKeyInput.isEmpty {
                Label("Stored securely in macOS Keychain", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundColor(.green)
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
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Hotkey", icon: "keyboard")
            HStack {
                Text("Current hotkey")
                Spacer()
                Text("⌘⇧K")
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlColor))
                    .cornerRadius(6)
            }
            Text("Hotkey rebinding comes in v1.1. If ⌘⇧K conflicts with Slack, reassign Slack's shortcut in System Settings › Keyboard › App Shortcuts.")
                .font(.caption)
                .foregroundColor(.secondary)
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
        KeychainManager.shared.apiKey = apiKeyInput
        settings.persist()
        withAnimation { savedFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { savedFlash = false }
        }
    }
}
