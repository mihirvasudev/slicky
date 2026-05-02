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
            captureSource: context.source,
            onAccept: { [weak self] in self?.acceptRewrite() },
            onCancel: { [weak self] in self?.dismiss() }
        )

        let hostingView = NSHostingView(rootView: hudView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 620, height: 580)

        // .nonActivatingPanel was removed from macOS 15 SDK; we need activation anyway
        // for the local key-event monitor to fire.
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 580),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = NSWindow.TitleVisibility.hidden
        panel.isMovableByWindowBackground = true
        panel.level = NSWindow.Level.floating
        panel.isFloatingPanel = true
        panel.collectionBehavior = NSWindow.CollectionBehavior([.canJoinAllSpaces, .fullScreenAuxiliary])
        panel.contentView = hostingView
        panel.center()

        // Hide traffic light buttons
        panel.standardWindowButton(NSWindow.ButtonType.closeButton)?.isHidden = true
        panel.standardWindowButton(NSWindow.ButtonType.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(NSWindow.ButtonType.zoomButton)?.isHidden = true

        self.window = panel

        // Install keyboard handler before showing
        vm.installKeyMonitor(
            onAccept: { [weak self] in self?.acceptRewrite() },
            onCancel: { [weak self] in self?.dismiss() }
        )

        // Activate app so the panel receives key events
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil as AnyObject?)

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
