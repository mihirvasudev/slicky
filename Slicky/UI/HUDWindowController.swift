import AppKit
import SwiftUI

final class HUDWindowController {
    private var window: NSWindow?
    private var viewModel: HUDViewModel?
    private let settings: SlickySettings
    private var capturedContext: CapturedContext?

    var isVisible: Bool { window?.isVisible ?? false }

    init(settings: SlickySettings) {
        self.settings = settings
    }

    @MainActor
    func show(context: CapturedContext) {
        capturedContext = context

        let vm = HUDViewModel()
        self.viewModel = vm

        let hudView = HUDView(
            viewModel: vm,
            originalText: context.selectedText,
            onAccept: { [weak self] in self?.acceptRewrite() },
            onCancel: { [weak self] in self?.dismiss() }
        )

        let hostingView = NSHostingView(rootView: hudView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 620, height: 580)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 580),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonActivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hostingView
        panel.center()

        // Hide traffic light buttons
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        self.window = panel

        // Install keyboard handler before showing
        vm.installKeyMonitor(
            onAccept: { [weak self] in self?.acceptRewrite() },
            onCancel: { [weak self] in self?.dismiss() }
        )

        // Activate app so the panel receives key events
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        // Start the agentic pipeline
        vm.startRewrite(context: context, settings: settings)
    }

    @MainActor
    private func acceptRewrite() {
        guard let vm = viewModel else { dismiss(); return }
        guard vm.isDone || vm.isFailed else {
            // Pipeline still running — wait for done
            if !vm.finalText.isEmpty {
                pasteAndDismiss(text: vm.isEditing ? vm.editedText : vm.finalText)
            }
            return
        }
        let text = vm.isEditing ? vm.editedText : vm.finalText
        pasteAndDismiss(text: text)
    }

    @MainActor
    private func pasteAndDismiss(text: String) {
        guard let context = capturedContext, !text.isEmpty else {
            dismiss()
            return
        }

        let windowToClose = window
        viewModel?.removeKeyMonitor()
        viewModel?.cancel()

        // Hide our panel first
        windowToClose?.orderOut(nil)
        self.window = nil
        self.viewModel = nil

        // Inject text (AX or clipboard fallback)
        TextInjector.shared.inject(text: text, context: context) {
            // Done
        }
    }

    @MainActor
    func dismiss() {
        viewModel?.cancel()
        viewModel?.removeKeyMonitor()
        window?.orderOut(nil)
        window = nil
        viewModel = nil
        capturedContext = nil
    }
}
