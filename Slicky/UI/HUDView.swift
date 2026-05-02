import AppKit
import SwiftUI

struct HUDView: View {
    @ObservedObject var viewModel: HUDViewModel
    let originalText: String
    let captureSource: CaptureSource
    let captureSourceDisplay: String
    let warnStaleClipboard: Bool
    let onAccept: () -> Void
    let onCancel: () -> Void

    // Original is collapsed for AX selection (the user knows what they
    // selected), but expanded for clipboard/synthetic so they can sanity-check
    // it caught the right text before the LLM runs.
    @State private var showOriginal: Bool
    @State private var showCritique = false

    init(viewModel: HUDViewModel, originalText: String, captureSource: CaptureSource, captureSourceDisplay: String, warnStaleClipboard: Bool, onAccept: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.viewModel = viewModel
        self.originalText = originalText
        self.captureSource = captureSource
        self.captureSourceDisplay = captureSourceDisplay
        self.warnStaleClipboard = warnStaleClipboard
        self.onAccept = onAccept
        self.onCancel = onCancel
        self._showOriginal = State(initialValue: captureSource != .axSelection)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    originalSection
                    if viewModel.isFailed, let message = viewModel.errorMessage {
                        failureSection(message: message)
                    } else {
                        pipelineSection
                        if viewModel.isDone || !viewModel.finalText.isEmpty {
                            finalSection
                        }
                    }
                }
                .padding(20)
            }
            Divider()
            footerBar
        }
        .frame(width: 620, height: 580)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func failureSection(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundColor(.red)
                Text("Slicky couldn't finish the rewrite")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            Text(message)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Press Esc to dismiss, then edit the original or try a different model in Settings.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.red.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(10)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Image(systemName: "wand.and.stars")
                .foregroundColor(.accentColor)
            Text("Slicky")
                .fontWeight(.semibold)
            captureSourceBadge
            if let intent = viewModel.classifiedIntent {
                Capsule()
                    .fill(intentColor(intent).opacity(0.2))
                    .overlay(
                        Text("\(intent.emoji) \(intent.displayName)")
                            .font(.caption)
                            .foregroundColor(intentColor(intent))
                            .padding(.horizontal, 8)
                    )
                    .frame(height: 22)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Spacer()
            stageIndicator
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var captureSourceBadge: some View {
        let icon: String
        switch captureSource {
        case .axSelection:    icon = "text.cursor"
        case .clipboardLive:  icon = "doc.on.clipboard"
        case .syntheticCopy:  icon = "rectangle.on.rectangle.angled"
        }
        let isWarn = warnStaleClipboard
        return HStack(spacing: 4) {
            Image(systemName: isWarn ? "exclamationmark.triangle.fill" : icon).font(.caption2)
            Text(captureSourceDisplay).font(.caption)
        }
        .foregroundColor(isWarn ? .orange : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background((isWarn ? Color.orange : Color(NSColor.controlColor)).opacity(isWarn ? 0.18 : 0.6))
        .cornerRadius(6)
    }

    private var stageIndicator: some View {
        Group {
            switch viewModel.stage {
            case .idle:
                EmptyView()
            case .classifying:
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.6)
                    Text("Classifying…").font(.caption).foregroundColor(.secondary)
                }
            case .drafting:
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.6)
                    Text("Drafting…").font(.caption).foregroundColor(.secondary)
                }
            case .critiquing:
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.6)
                    Text("Critiquing…").font(.caption).foregroundColor(.secondary)
                }
            case .refining:
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.6)
                    Text("Refining…").font(.caption).foregroundColor(.secondary)
                }
            case .done:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
                    Text("Done").font(.caption).foregroundColor(.green)
                }
            case .failed:
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red).font(.caption)
                    Text("Error").font(.caption).foregroundColor(.red)
                }
            }
        }
    }

    // MARK: - Original

    private var originalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { showOriginal.toggle() }) {
                HStack {
                    Image(systemName: showOriginal ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text(originalSectionLabel)
                        .font(.caption)
                        .foregroundColor(captureSource == .axSelection ? .secondary : .accentColor)
                    Spacer()
                    if captureSource != .axSelection {
                        Text("Esc to cancel if this is wrong")
                            .font(.caption2)
                            .foregroundColor(Color.secondary.opacity(0.7))
                    }
                }
            }
            .buttonStyle(.plain)

            if showOriginal {
                Text(originalText)
                    .font(.system(size: 12, design: captureSource == .clipboardLive ? .monospaced : .default))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var originalSectionLabel: String {
        switch captureSource {
        case .axSelection:    return "Original prompt"
        case .clipboardLive:
            let age = captureSourceDisplay.replacingOccurrences(of: "from clipboard · ", with: "")
            return "Rewriting clipboard text (\(age)) — verify ↓"
        case .syntheticCopy:  return "Rewriting auto-copied selection — verify ↓"
        }
    }

    // MARK: - Pipeline

    private var pipelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.draftText.isEmpty {
                stageBlock(label: "Draft", systemImage: "pencil", color: .blue) {
                    StreamingText(text: viewModel.draftText, isDone: viewModel.stage != .drafting && viewModel.stage != .classifying)
                }
            }

            if !viewModel.critiqueIssues.isEmpty || viewModel.critiqueScore > 0 {
                DisclosureGroup(isExpanded: $showCritique) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.critiqueIssues, id: \.self) { issue in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                Text(issue).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    HStack {
                        Image(systemName: "checkmark.shield")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("Critique · Score \(viewModel.critiqueScore)/10")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if !viewModel.refinedText.isEmpty {
                stageBlock(label: "Refined", systemImage: "sparkles", color: .purple) {
                    StreamingText(text: viewModel.refinedText, isDone: viewModel.isDone)
                }
            }
        }
    }

    @ViewBuilder
    private func stageBlock<Content: View>(label: String, systemImage: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.caption).foregroundColor(color)
                Text(label).font(.caption).foregroundColor(color)
            }
            content()
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
        }
    }

    // MARK: - Final

    private var finalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "star.fill").font(.caption).foregroundColor(.yellow)
                Text("Rewritten prompt")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if viewModel.isDone && !viewModel.isEditing {
                    Text("Tab to edit")
                        .font(.caption2)
                        .foregroundColor(Color.secondary.opacity(0.7))
                }
            }

            if viewModel.isEditing {
                TextEditor(text: $viewModel.editedText)
                    .font(.system(size: 13))
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor.opacity(0.5), lineWidth: 1.5)
                    )
            } else {
                Text(viewModel.finalText)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                    )
            }

            if let error = viewModel.errorMessage {
                Text("Error: \(error)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
            }
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 16) {
            shortcut("↩", label: viewModel.isEditing ? "⌘↩ Paste" : "Paste")
                .onTapGesture { onAccept() }
            shortcut("⎋", label: "Cancel")
                .onTapGesture { onCancel() }
            if viewModel.isDone && !viewModel.isEditing {
                shortcut("⇥", label: "Edit")
                    .onTapGesture { viewModel.isEditing = true }
            }
            Spacer()
            Button(action: copyToClipboard) {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.finalText.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func shortcut(_ key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color(NSColor.controlColor))
                .cornerRadius(4)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private func copyToClipboard() {
        let text = viewModel.isEditing ? viewModel.editedText : viewModel.finalText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func intentColor(_ intent: Intent) -> Color {
        switch intent {
        case .codingFeature:  return .blue
        case .codingBug:      return .red
        case .codingRefactor: return .orange
        case .writing:        return .green
        case .research:       return .purple
        case .general:        return .gray
        }
    }
}

// MARK: - Streaming text view

private struct StreamingText: View {
    let text: String
    let isDone: Bool

    var body: some View {
        HStack(alignment: .top) {
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(Color(NSColor.labelColor))
                .frame(maxWidth: .infinity, alignment: .leading)
            if !isDone {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: 14)
                    .opacity(0.8)
                    .animation(.easeInOut(duration: 0.5).repeatForever(), value: isDone)
            }
        }
    }
}
