import SwiftUI
import ApplicationServices

struct OnboardingView: View {
    @ObservedObject var settings: SlickySettings
    let onComplete: () -> Void

    @State private var apiKey: String = ""
    @State private var step: Int = 0
    @State private var axTrusted: Bool = AXIsProcessTrusted()
    @State private var apiKeySaveError: String?

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            Divider()

            TabView(selection: $step) {
                welcomeStep.tag(0)
                apiKeyStep.tag(1)
                accessibilityStep.tag(2)
                readyStep.tag(3)
            }
            .tabViewStyle(.automatic)

            Divider()

            navigationButtons
        }
        .frame(width: 520, height: 460)
        .onAppear {
            apiKey = KeychainManager.shared.apiKey
            axTrusted = AXIsProcessTrusted()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "wand.and.stars")
                .font(.title2)
                .foregroundColor(.accentColor)
            Text("Welcome to Slicky")
                .font(.headline)
            Spacer()
            Text("\(step + 1) / 4")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text("Turn sloppy prompts into great ones")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text("Select any text → press \(settings.hotkeyDisplayString) → watch Slicky rewrite it into a structured, high-leverage prompt with phases, tests, and acceptance criteria.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 10) {
                featureRow("Works everywhere", detail: "Cursor, Claude Code, Terminal, claude.ai, Slack, Notion", icon: "globe")
                featureRow("Agentic pipeline", detail: "Classify → Draft → Critique → Refine — live streaming", icon: "sparkles")
                featureRow("Intent-aware", detail: "Different structure for feature requests vs bug fixes vs writing", icon: "brain")
                featureRow("Private by default", detail: "Your API key, stored in macOS Keychain. No backend.", icon: "lock.shield")
            }
            .padding(.horizontal, 20)
        }
        .padding(24)
    }

    private var apiKeyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text("Add your Anthropic API key")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Slicky uses Claude to rewrite prompts. Your key is stored only in macOS Keychain — never sent to any server except Anthropic.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 8) {
                SecureField("sk-ant-api03-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 360)

                HStack(spacing: 4) {
                    Text("Get a key at")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Link("console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                        .font(.caption)
                }
            }

            if !apiKey.isEmpty {
                Label("Key will be saved securely on Next", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            if let apiKeySaveError {
                Label(apiKeySaveError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(24)
    }

    private var accessibilityStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "accessibility")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text("Enable Accessibility access")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Slicky needs Accessibility permission to read your selected text and paste the rewrite back — without this, it can't do anything.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: axTrusted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(axTrusted ? .green : .gray)
                    Text(axTrusted ? "Accessibility granted" : "Not yet granted")
                }
                .font(.body)

                if !axTrusted {
                    Button("Open System Settings → Accessibility") {
                        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                        AXIsProcessTrustedWithOptions(opts)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            axTrusted = AXIsProcessTrusted()
                        }
                    }
                    .controlSize(.large)
                }

                Button("Refresh Permission Status") {
                    axTrusted = AXIsProcessTrusted()
                }
                .controlSize(.small)

                Text("System Settings → Privacy & Security → Accessibility → toggle Slicky")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
    }

    private var readyStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 50))
                .foregroundColor(.yellow)

            VStack(spacing: 8) {
                Text("You're ready!")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Slicky lives in your menu bar. Select any prompt text, press \(settings.hotkeyDisplayString), and watch the magic.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 8) {
                tipRow("Select your sloppy prompt text first", icon: "cursor.rays")
                tipRow("Press \(settings.hotkeyDisplayString) (or your custom hotkey)", icon: "keyboard")
                tipRow("Watch the pipeline — Draft → Critique → Refine", icon: "eyes")
                tipRow("Press Return to paste, Tab to edit, Esc to cancel", icon: "return")
            }
            .padding(.horizontal, 20)
        }
        .padding(24)
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.bordered)
            }
            Spacer()
            if step < 3 {
                Button("Next") { advanceStep() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdvance)
            } else {
                Button("Start using Slicky") {
                    guard apiKey.isEmpty || KeychainManager.shared.saveAPIKey(apiKey) else {
                        apiKeySaveError = "Could not save API key. Please try again."
                        step = 1
                        return
                    }
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canFinish)
            }
        }
        .padding(20)
    }

    private var canAdvance: Bool {
        if step == 1 { return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if step == 2 { return axTrusted }
        return true
    }

    private var canFinish: Bool {
        (!apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !KeychainManager.shared.apiKey.isEmpty)
            && axTrusted
    }

    private func advanceStep() {
        if step == 1 && !apiKey.isEmpty {
            guard KeychainManager.shared.saveAPIKey(apiKey) else {
                apiKeySaveError = "Could not save API key. Please try again."
                return
            }
            apiKeySaveError = nil
        }
        step += 1
    }

    // MARK: - Helpers

    private func featureRow(_ title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func tipRow(_ text: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 20)
            Text(text).font(.body)
        }
    }
}
