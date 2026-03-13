import AppKit
import SwiftUI

/// Manages the floating overlay panel that shows transcription status and results.
///
/// The overlay is an `NSPanel` configured to:
/// - Float above all windows (non-activating, so focus stays in the user's app)
/// - Position near the mouse cursor when shown
/// - Auto-dismiss after a configurable delay for transcription results
/// - Fade in and out with animation
final class OverlayWindowController {

    // MARK: - Configuration

    /// How long (in seconds) the overlay stays visible after showing a transcription result.
    var resultDismissDelay: TimeInterval = 3.0

    // MARK: - Private State

    private var panel: NSPanel?
    private var hostingView: NSHostingView<OverlayView>?
    private var dismissWorkItem: DispatchWorkItem?
    private var currentStatus: TranscriptionStatus = .idle
    private var currentTranscription: String = ""

    // MARK: - Public API

    /// Show the overlay with a listening indicator near the mouse cursor.
    func showListening() {
        cancelAutoDismiss()
        currentStatus = .listening
        currentTranscription = ""
        showPanel()
    }

    /// Update the overlay to show a processing indicator.
    func showProcessing() {
        cancelAutoDismiss()
        currentStatus = .processing
        currentTranscription = ""
        showPanel()
    }

    /// Show the transcription result, then auto-dismiss after a delay.
    func showResult(_ text: String) {
        cancelAutoDismiss()
        currentStatus = .idle
        currentTranscription = text
        showPanel()
        scheduleAutoDismiss()
    }

    /// Dismiss the overlay immediately.
    func dismiss() {
        cancelAutoDismiss()
        guard let panelToClose = panel else { return }
        // Clear references immediately so concurrent showPanel() creates a fresh panel
        self.panel = nil
        self.hostingView = nil

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panelToClose.animator().alphaValue = 0
        } completionHandler: {
            panelToClose.orderOut(nil)
        }
    }

    /// Whether the overlay is currently visible.
    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    // MARK: - Private

    private func showPanel() {
        if panel == nil {
            createPanel()
        }
        updateContent()
        positionNearMouse()

        panel?.alphaValue = 0
        panel?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.panel?.animator().alphaValue = 1
        }
    }

    private func createPanel() {
        let overlayView = OverlayView(
            status: currentStatus,
            transcription: currentTranscription
        )
        let hosting = NSHostingView(rootView: overlayView)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        // Size to fit content
        let fittingSize = hosting.fittingSize
        let contentRect = NSRect(x: 0, y: 0, width: max(fittingSize.width, 180), height: max(fittingSize.height, 40))

        let panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // We use SwiftUI shadow instead
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.contentView = hosting

        // Auto-size with content
        hosting.frame = panel.contentView?.bounds ?? contentRect
        hosting.autoresizingMask = [.width, .height]

        self.panel = panel
        self.hostingView = hosting
    }

    private func updateContent() {
        let overlayView = OverlayView(
            status: currentStatus,
            transcription: currentTranscription
        )
        hostingView?.rootView = overlayView

        // Re-fit the panel to the new content size
        if let hosting = hostingView {
            let fittingSize = hosting.fittingSize
            let newSize = NSSize(
                width: max(fittingSize.width, 180),
                height: max(fittingSize.height, 40)
            )
            panel?.setContentSize(newSize)
        }
    }

    private func positionNearMouse() {
        guard let panel else { return }

        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
                ?? NSScreen.main else { return }

        let panelSize = panel.frame.size
        let screenFrame = screen.visibleFrame

        // Position slightly below and to the right of the cursor
        var origin = NSPoint(
            x: mouseLocation.x + 16,
            y: mouseLocation.y - panelSize.height - 16
        )

        // Keep on screen
        if origin.x + panelSize.width > screenFrame.maxX {
            origin.x = mouseLocation.x - panelSize.width - 16
        }
        if origin.y < screenFrame.minY {
            origin.y = mouseLocation.y + 24
        }
        if origin.x < screenFrame.minX {
            origin.x = screenFrame.minX + 8
        }

        panel.setFrameOrigin(origin)
    }

    private func scheduleAutoDismiss() {
        let workItem = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + resultDismissDelay, execute: workItem)
    }

    private func cancelAutoDismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }
}
