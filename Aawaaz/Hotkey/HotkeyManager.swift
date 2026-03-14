import AppKit

/// Manages global hotkey registration and detection for dictation activation.
///
/// Uses a **CGEvent tap** (preferred) to intercept and suppress keyboard events
/// system-wide so the activation shortcut does not leak into the frontmost app.
///
/// If the CGEvent tap cannot be created (e.g. Accessibility permission not yet
/// granted), falls back to `NSEvent` global/local monitors which observe but
/// cannot suppress events.
///
/// Supports both hold-to-talk and toggle activation modes.
final class HotkeyManager {

    // MARK: - Callbacks

    /// Called when the hotkey activates (start dictation).
    var onActivate: (() -> Void)?

    /// Called when the hotkey deactivates (stop dictation, hold mode only).
    var onDeactivate: (() -> Void)?

    // MARK: - Configuration

    private(set) var configuration: HotkeyConfiguration

    // MARK: - Public State

    /// Whether the event tap is active (i.e. hotkey events are being suppressed).
    /// When `false`, the manager is using the fallback NSEvent monitors.
    private(set) var isEventTapActive = false

    // MARK: - CGEvent Tap State

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - NSEvent Fallback State

    private var globalKeyDownMonitor: Any?
    private var globalKeyUpMonitor: Any?
    private var globalFlagsChangedMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var localKeyUpMonitor: Any?
    private var localFlagsChangedMonitor: Any?

    // MARK: - Activation State

    private var isHoldActive = false
    private var isToggleActive = false

    // MARK: - Init

    init(configuration: HotkeyConfiguration = .load()) {
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Start monitoring for the configured hotkey.
    ///
    /// Attempts to install a CGEvent tap first. If that fails (no Accessibility
    /// permission), falls back to NSEvent monitors.
    func startMonitoring() {
        stopMonitoring()

        if installEventTap() {
            isEventTapActive = true
        } else {
            // Accessibility not granted — use observer-only monitors as fallback.
            installNSEventMonitors()
            isEventTapActive = false
        }
    }

    /// Stop monitoring for hotkey events.
    func stopMonitoring() {
        removeEventTap()
        removeNSEventMonitors()
        isHoldActive = false
        isToggleActive = false
        isEventTapActive = false
    }

    /// Update the hotkey configuration and restart monitoring.
    func updateConfiguration(_ newConfig: HotkeyConfiguration) {
        configuration = newConfig
        newConfig.save()

        let wasMonitoring = eventTap != nil || globalKeyDownMonitor != nil || globalFlagsChangedMonitor != nil
        if wasMonitoring {
            stopMonitoring()
            startMonitoring()
        }
    }

    /// Re-attempt installing a CGEvent tap if currently using the NSEvent
    /// fallback. Call this after Accessibility permission is granted at runtime.
    func upgradeToEventTapIfPossible() {
        guard !isEventTapActive,
              globalKeyDownMonitor != nil || globalFlagsChangedMonitor != nil else { return }
        // Try to upgrade — startMonitoring will prefer the tap.
        stopMonitoring()
        startMonitoring()
    }

    /// Reset any active hold/toggle state (e.g., when pipeline stops externally).
    func resetState() {
        isHoldActive = false
        isToggleActive = false
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - CGEvent Tap

    /// Install a CGEvent tap that can intercept and suppress keyboard events.
    /// Returns `true` on success, `false` if the tap could not be created.
    private func installEventTap() -> Bool {
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyEventTapCallback,
            userInfo: selfPointer
        ) else {
            return false
        }

        eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        return true
    }

    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// Called from the CGEvent tap callback. Returns `nil` to suppress the event,
    /// or the original event to pass it through.
    ///
    /// **Memory note**: The caller (Quartz) retains the event before invoking the
    /// callback and releases it after the callback returns. We must return
    /// `passUnretained` for passthrough events to avoid leaking an extra retain.
    fileprivate func handleCGEvent(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {

        // Re-enable the tap if the system disabled it (e.g. timeout).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        guard keyCode == configuration.keyCode else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            // On keyDown, verify modifiers match.
            let relevantCGFlags: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
            let eventMods = event.flags.intersection(relevantCGFlags)
            let configMods = Self.cgEventFlags(from: NSEvent.ModifierFlags(rawValue: configuration.modifierFlags))

            guard eventMods == configMods else {
                return Unmanaged.passUnretained(event)
            }

            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if isRepeat {
                return nil // Suppress repeats silently
            }

            switch configuration.mode {
            case .hold:
                guard !isHoldActive else { return nil }
                isHoldActive = true
                DispatchQueue.main.async { [weak self] in self?.onActivate?() }

            case .toggle:
                if isToggleActive {
                    isToggleActive = false
                    DispatchQueue.main.async { [weak self] in self?.onDeactivate?() }
                } else {
                    isToggleActive = true
                    DispatchQueue.main.async { [weak self] in self?.onActivate?() }
                }
            }

            return nil // Suppress

        } else if type == .keyUp {
            // On keyUp only check keyCode (modifiers may already be released).
            switch configuration.mode {
            case .hold:
                guard isHoldActive else { return Unmanaged.passUnretained(event) }
                isHoldActive = false
                DispatchQueue.main.async { [weak self] in self?.onDeactivate?() }
                return nil

            case .toggle:
                return Unmanaged.passUnretained(event)
            }

        } else if type == .flagsChanged {
            // Handle modifier-only keys (like Fn/Globe).
            guard configuration.isModifierOnlyKey,
                  keyCode == configuration.keyCode,
                  let flag = Self.cgModifierFlag(for: keyCode) else {
                return Unmanaged.passUnretained(event)
            }

            // Check additional modifiers match (if any configured).
            let relevantCGFlags: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
            let eventMods = event.flags.intersection(relevantCGFlags)
            let configMods = Self.cgEventFlags(from: NSEvent.ModifierFlags(rawValue: configuration.modifierFlags))
            guard eventMods == configMods else {
                return Unmanaged.passUnretained(event)
            }

            let isPressed = event.flags.contains(flag)

            if isPressed {
                switch configuration.mode {
                case .hold:
                    guard !isHoldActive else { return nil }
                    isHoldActive = true
                    DispatchQueue.main.async { [weak self] in self?.onActivate?() }
                case .toggle:
                    if isToggleActive {
                        isToggleActive = false
                        DispatchQueue.main.async { [weak self] in self?.onDeactivate?() }
                    } else {
                        isToggleActive = true
                        DispatchQueue.main.async { [weak self] in self?.onActivate?() }
                    }
                }
            } else {
                switch configuration.mode {
                case .hold:
                    guard isHoldActive else { return Unmanaged.passUnretained(event) }
                    isHoldActive = false
                    DispatchQueue.main.async { [weak self] in self?.onDeactivate?() }
                case .toggle:
                    break // No action on release in toggle mode
                }
            }

            return nil // Suppress
        }

        return Unmanaged.passUnretained(event)
    }

    /// Convert `NSEvent.ModifierFlags` to the equivalent `CGEventFlags` mask.
    private static func cgEventFlags(from nsFlags: NSEvent.ModifierFlags) -> CGEventFlags {
        var result: CGEventFlags = []
        if nsFlags.contains(.shift) { result.insert(.maskShift) }
        if nsFlags.contains(.control) { result.insert(.maskControl) }
        if nsFlags.contains(.option) { result.insert(.maskAlternate) }
        if nsFlags.contains(.command) { result.insert(.maskCommand) }
        return result
    }

    /// Map a modifier key code to its corresponding `CGEventFlags` flag.
    private static func cgModifierFlag(for keyCode: UInt16) -> CGEventFlags? {
        switch keyCode {
        case 54, 55: return .maskCommand     // Right/Left Command
        case 56, 60: return .maskShift        // Left/Right Shift
        case 58, 61: return .maskAlternate    // Left/Right Option
        case 59, 62: return .maskControl      // Left/Right Control
        case 63:     return .maskSecondaryFn  // Fn / Globe
        default:     return nil
        }
    }

    /// Map a modifier key code to its corresponding `NSEvent.ModifierFlags` flag.
    private static func nsModifierFlag(for keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 54, 55: return .command   // Right/Left Command
        case 56, 60: return .shift     // Left/Right Shift
        case 58, 61: return .option    // Left/Right Option
        case 59, 62: return .control   // Left/Right Control
        case 63:     return .function  // Fn / Globe
        default:     return nil
        }
    }

    // MARK: - NSEvent Fallback

    /// Install observer-only NSEvent monitors as a fallback when the CGEvent tap
    /// is unavailable. Events are NOT suppressed in this mode.
    private func installNSEventMonitors() {
        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }
        globalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleKeyUp(event)
        }
        globalFlagsChangedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyDown(event) == true {
                return nil
            }
            return event
        }
        localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            if self?.handleKeyUp(event) == true {
                return nil
            }
            return event
        }
        localFlagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if self?.handleFlagsChanged(event) == true {
                return nil
            }
            return event
        }
    }

    private func removeNSEventMonitors() {
        if let monitor = globalKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyDownMonitor = nil
        }
        if let monitor = globalKeyUpMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyUpMonitor = nil
        }
        if let monitor = globalFlagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
            globalFlagsChangedMonitor = nil
        }
        if let monitor = localKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyDownMonitor = nil
        }
        if let monitor = localKeyUpMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyUpMonitor = nil
        }
        if let monitor = localFlagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
            localFlagsChangedMonitor = nil
        }
    }

    /// Handle key down events (NSEvent fallback). Returns `true` if the event was consumed.
    @discardableResult
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard configuration.matches(event) else { return false }
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

    /// Handle key up events (NSEvent fallback). Returns `true` if the event was consumed.
    @discardableResult
    private func handleKeyUp(_ event: NSEvent) -> Bool {
        guard event.keyCode == configuration.keyCode else { return false }

        switch configuration.mode {
        case .hold:
            guard isHoldActive else { return false }
            isHoldActive = false
            onDeactivate?()
            return true

        case .toggle:
            return false
        }
    }

    /// Handle flags-changed events for modifier-only hotkeys (NSEvent fallback).
    /// Returns `true` if the event was consumed.
    @discardableResult
    private func handleFlagsChanged(_ event: NSEvent) -> Bool {
        guard configuration.isModifierOnlyKey,
              event.keyCode == configuration.keyCode,
              let flag = Self.nsModifierFlag(for: event.keyCode) else {
            return false
        }

        // Check additional modifiers match (if any configured).
        let relevantModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
        let eventMods = event.modifierFlags.intersection(relevantModifiers)
        let configMods = NSEvent.ModifierFlags(rawValue: configuration.modifierFlags).intersection(relevantModifiers)
        guard eventMods == configMods else { return false }

        let isPressed = event.modifierFlags.contains(flag)

        if isPressed {
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
        } else {
            switch configuration.mode {
            case .hold:
                guard isHoldActive else { return false }
                isHoldActive = false
                onDeactivate?()
            case .toggle:
                break
            }
        }
        return true
    }
}

// MARK: - CGEvent Tap C Callback

/// Top-level C-compatible callback for the CGEvent tap.
private func hotkeyEventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    return manager.handleCGEvent(type: type, event: event)
}
