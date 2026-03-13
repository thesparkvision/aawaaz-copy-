import AppKit

/// Manages global hotkey registration and detection for dictation activation.
///
/// Uses `NSEvent` global and local monitors to detect the configured keyboard shortcut.
/// Supports both hold-to-talk (key down → start, key up → stop) and toggle
/// (key down → toggle) activation modes.
///
/// The implementation uses two monitor types:
/// - **Global monitor**: Detects events when the app is NOT focused (system-wide)
/// - **Local monitor**: Detects events when the app IS focused
///
/// **Important**: Global key event monitors require Input Monitoring (Accessibility)
/// permission on macOS. Without it, key events will silently not be received.
/// The app guides the user to grant this permission during onboarding.
final class HotkeyManager {

    // MARK: - Callbacks

    /// Called when the hotkey activates (start dictation).
    var onActivate: (() -> Void)?

    /// Called when the hotkey deactivates (stop dictation, hold mode only).
    var onDeactivate: (() -> Void)?

    // MARK: - Configuration

    private(set) var configuration: HotkeyConfiguration

    // MARK: - Private State

    private var globalKeyDownMonitor: Any?
    private var globalKeyUpMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var localKeyUpMonitor: Any?
    private var isHoldActive = false
    private var isToggleActive = false

    // MARK: - Init

    init(configuration: HotkeyConfiguration = .load()) {
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Start monitoring for the configured hotkey.
    func startMonitoring() {
        stopMonitoring()

        // Global monitors: detect events when app is NOT focused
        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }
        globalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleKeyUp(event)
        }

        // Local monitors: detect events when app IS focused
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyDown(event) == true {
                return nil // Consume the event
            }
            return event
        }
        localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            if self?.handleKeyUp(event) == true {
                return nil
            }
            return event
        }
    }

    /// Stop monitoring for hotkey events.
    func stopMonitoring() {
        if let monitor = globalKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyDownMonitor = nil
        }
        if let monitor = globalKeyUpMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyUpMonitor = nil
        }
        if let monitor = localKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyDownMonitor = nil
        }
        if let monitor = localKeyUpMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyUpMonitor = nil
        }

        isHoldActive = false
        isToggleActive = false
    }

    /// Update the hotkey configuration and restart monitoring.
    func updateConfiguration(_ newConfig: HotkeyConfiguration) {
        configuration = newConfig
        newConfig.save()

        // Restart monitors with new configuration
        let wasMonitoring = globalKeyDownMonitor != nil
        if wasMonitoring {
            stopMonitoring()
            startMonitoring()
        }
    }

    /// Reset any active hold/toggle state (e.g., when pipeline stops externally).
    func resetState() {
        isHoldActive = false
        isToggleActive = false
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Event Handling

    /// Handle key down events. Returns `true` if the event was consumed.
    @discardableResult
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard configuration.matches(event) else { return false }
        // Ignore key repeats (held keys fire repeated keyDown events)
        guard !event.isARepeat else { return true }

        switch configuration.mode {
        case .hold:
            guard !isHoldActive else { return true }
            isHoldActive = true
            onActivate?()

        case .toggle:
            if isToggleActive {
                isToggleActive = false
                onDeactivate?()
            } else {
                isToggleActive = true
                onActivate?()
            }
        }
        return true
    }

    /// Handle key up events. Returns `true` if the event was consumed.
    @discardableResult
    private func handleKeyUp(_ event: NSEvent) -> Bool {
        // For key up, we only check the key code (modifiers may already be released)
        guard event.keyCode == configuration.keyCode else { return false }

        switch configuration.mode {
        case .hold:
            guard isHoldActive else { return false }
            isHoldActive = false
            onDeactivate?()
            return true

        case .toggle:
            // Toggle mode doesn't respond to key up
            return false
        }
    }
}
