import AppKit
import SwiftUI

/// Manages the floating overlay panel that shows transcription status and results.
///
/// The overlay is an `NSPanel` configured to:
/// - Float above all windows (non-activating, so focus stays in the user's app)
/// - Position at the bottom center of the screen
/// - Auto-dismiss after a configurable delay for transcription results
/// - Fade in and out with animation
///
/// All public methods must be called on the main thread.
final class OverlayWindowController {

    // MARK: - Configuration

    /// How long (in seconds) the overlay stays visible after showing a transcription result.
    var resultDismissDelay: TimeInterval = 3.0

    // MARK: - Private State

    private var panel: NSPanel?
    private var hostingView: NSHostingView<OverlayView>?
    private var dismissWorkItem: DispatchWorkItem?
    let overlayState = OverlayState()

    // MARK: - Public API

    /// Show the overlay with a listening indicator at the bottom center of the screen.
    func showListening() {
        cancelAutoDismiss()
        overlayState.status = .listening
        overlayState.transcription = ""
        overlayState.amplitude = 0
        showPanel()
    }

    /// Update the overlay to show a processing indicator.
    func showProcessing() {
        cancelAutoDismiss()
        overlayState.status = .processing
        overlayState.amplitude = 0
        showPanel()
    }

    /// Show the transcription result, then auto-dismiss after a delay.
    func showResult(_ text: String) {
        cancelAutoDismiss()
        overlayState.status = .idle
        overlayState.transcription = text
        overlayState.amplitude = 0
        showPanel()
        scheduleAutoDismiss()
    }

    /// Update the current audio amplitude (0–1). Only takes effect while listening.
    func updateAmplitude(_ amplitude: Float) {
        guard overlayState.status == .listening else { return }
        overlayState.amplitude = amplitude
    }

    /// Update the interim transcription text while still listening.
    ///
    /// Shows accumulated Whisper output in the overlay so the user sees their
    /// speech being captured in real time. The waveform continues animating.
    func updateInterimText(_ text: String) {
        guard overlayState.status == .listening || overlayState.status == .processing else { return }
        overlayState.status = .listening
        overlayState.transcription = text
        showPanel()
        // Defer resize so SwiftUI layout reflects the new text
        DispatchQueue.main.async { [weak self] in
            self?.resizeToFit()
        }
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

        if panel?.isVisible != true {
            // First show — position, fade in
            resizeToFit()
            positionBottomCenter()
            panel?.alphaValue = 0
            panel?.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                self.panel?.animator().alphaValue = 1
            }
        } else {
            panel?.orderFrontRegardless()
        }

        // Defer a resize pass so SwiftUI's reactive layout is reflected.
        DispatchQueue.main.async { [weak self] in
            self?.resizeToFit()
        }
    }

    private func createPanel() {
        let overlayView = OverlayView(state: overlayState)
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

    private func resizeToFit() {
        if let hosting = hostingView {
            let fittingSize = hosting.fittingSize
            let newSize = NSSize(
                width: max(fittingSize.width, 180),
                height: max(fittingSize.height, 40)
            )
            panel?.setContentSize(newSize)
        }
    }

    private func positionBottomCenter() {
        guard let panel else { return }

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
        guard let screen else { return }

        let panelSize = panel.frame.size
        let screenFrame = screen.visibleFrame

        // Center horizontally, place near the bottom with some padding
        let origin = NSPoint(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.minY + 40
        )

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
