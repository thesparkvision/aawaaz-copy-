import AppKit
import SwiftUI

/// Manages the onboarding window lifecycle.
///
/// Creates and shows an NSWindow with the onboarding SwiftUI view on first launch.
/// This is done programmatically because SwiftUI `Window` scenes don't auto-present
/// reliably for menu bar apps (LSUIElement).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var onboardingWindow: NSWindow?
    private var onboardingHosting: NSHostingController<AnyView>?

    func showOnboardingWindow(appState: AppState) {
        guard onboardingWindow == nil else {
            onboardingWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let onboardingView = AnyView(
            OnboardingView()
                .environment(appState)
        )

        let hosting = NSHostingController(rootView: onboardingView)
        self.onboardingHosting = hosting

        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Aawaaz"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 520, height: 480))
        window.center()
        window.isReleasedWhenClosed = false

        self.onboardingWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Dismiss the onboarding window.
    func dismissOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
        onboardingHosting = nil
    }
}
