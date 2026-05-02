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
    @State private var diagnosticReport: CaptureCoordinator.DiagnosticReport?
    @State private var probeStatus: ProbeStatus = .idle

    enum ProbeStatus {
        case idle
        case running
        case success(String)
        case failure(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                apiKeySection
                Divider()
                modelSection
                Divider()
                captureSection
                Divider()
                hotkeySection
                Divider()
                permissionsSection
                Divider()
                saveSection
            }
            .padding(24)
        }
        .frame(width: 520, height: 640)
        .onAppear {
            apiKeyInput = KeychainManager.shared.apiKey
            axTrusted = AXIsProcessTrusted()
        }
        .onChange(of: settings.draftModel) { _ in settings.persist() }
        .onChange(of: settings.classifyModel) { _ in settings.persist() }
        .onChange(of: settings.skipCritique) { _ in settings.persist() }
        .onChange(of: settings.captureStrategy) { _ in settings.persist() }
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

            HStack(spacing: 8) {
                Button {
                    probeAPIKey()
                } label: {
                    HStack(spacing: 6) {
                        if case .running = probeStatus {
                            ProgressView().scaleEffect(0.5)
                        } else {
                            Image(systemName: "checkmark.shield")
                        }
                        Text("Test API Key + Model")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(apiKeyInput.isEmpty || isProbing)

                probeStatusLabel
            }
        }
    }

    @ViewBuilder
    private var probeStatusLabel: some View {
        switch probeStatus {
        case .idle:
            EmptyView()
        case .running:
            Text("Pinging Anthropic…")
                .font(.caption)
                .foregroundColor(.secondary)
        case .success(let detail):
            Label(detail, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        case .failure(let detail):
            Label(detail, systemImage: "xmark.octagon.fill")
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var isProbing: Bool {
        if case .running = probeStatus { return true }
        return false
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

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Text capture", icon: "text.viewfinder")

            Picker("Strategy", selection: $settings.captureStrategy) {
                ForEach(SlickySettings.CaptureStrategy.allCases) { strategy in
                    Text(strategy.displayName).tag(strategy)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(settings.captureStrategy.explanation)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                runCaptureTest()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.circle")
                    Text("Test Capture")
                }
            }
            .buttonStyle(.bordered)
            .help("Switch to the app you want to capture from, select or copy text, come back here, and click this button.")

            if let report = diagnosticReport {
                diagnosticReportView(report)
            }
        }
    }

    @ViewBuilder
    private func diagnosticReportView(_ report: CaptureCoordinator.DiagnosticReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack {
                Image(systemName: report.chosenSource != nil ? "checkmark.seal.fill" : "exclamationmark.octagon.fill")
                    .foregroundColor(report.chosenSource != nil ? .green : .red)
                Text(report.chosenSource != nil
                     ? "Slicky would use \(label(for: report.chosenSource!))"
                     : "Slicky cannot capture text")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            if let app = report.appName.isEmpty ? nil : report.appName {
                detailRow("Front app", value: app)
            }
            if !report.bundleID.isEmpty {
                detailRow("Bundle ID", value: report.bundleID, secondary: true)
            }
            detailRow("AX selection", value: report.axTextPreview ?? "(none)")
            detailRow("Clipboard", value: report.clipboardTextPreview ?? "(empty)")
            detailRow("Clipboard age", value: report.clipboardAge, secondary: true)
            if let chosen = report.chosenTextPreview {
                detailRow("Will use", value: chosen, accent: true)
            }
            if let err = report.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func detailRow(_ label: String, value: String, accent: Bool = false, secondary: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundColor(accent ? .accentColor : (secondary ? .secondary : .primary))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func label(for source: CaptureSource) -> String {
        switch source {
        case .axSelection:    return "the live selection"
        case .clipboardLive:  return "the existing clipboard"
        case .syntheticCopy:  return "a synthetic auto-copy"
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

            HStack(spacing: 8) {
                Button("Refresh Permission Status") {
                    axTrusted = AXIsProcessTrusted()
                }
                .controlSize(.small)

                Text(axTrusted ? "Ready" : "Slicky cannot read selected text until this is granted.")
                    .font(.caption)
                    .foregroundColor(axTrusted ? .green : .secondary)
            }

            if let path = Bundle.main.bundleURL.path.removingPercentEncoding {
                Text("Running from: \(path)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
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

    private func probeAPIKey() {
        // Use the freshly-typed key if present, otherwise the persisted one.
        let key = apiKeyInput.isEmpty ? KeychainManager.shared.apiKey : apiKeyInput
        guard !key.isEmpty else {
            probeStatus = .failure("Enter an API key first.")
            return
        }
        probeStatus = .running
        let model = settings.draftModel.rawValue
        Task {
            let result = await AnthropicClient.shared.probe(model: model, apiKey: key)
            await MainActor.run {
                switch result {
                case .ok(let m, let sample):
                    let preview = sample.isEmpty ? "(empty reply)" : sample
                    probeStatus = .success("\(m) replied: \(preview)")
                case .unauthorized(let msg):
                    probeStatus = .failure("API key rejected (401). \(msg)")
                case .modelNotFound(let msg):
                    probeStatus = .failure("Model \(model) not found (404). Pick a different model above. \(msg)")
                case .other(let status, let msg):
                    probeStatus = .failure("HTTP \(status): \(msg)")
                case .transport(let err):
                    probeStatus = .failure("Network error: \(err.localizedDescription)")
                }
            }
        }
    }

    private func runCaptureTest() {
        // Run after a short delay so the user can switch to the target app.
        diagnosticReport = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            diagnosticReport = CaptureCoordinator.shared.dryRun(strategy: settings.captureStrategy)
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
