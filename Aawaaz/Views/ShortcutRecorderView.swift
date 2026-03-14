import SwiftUI
import AppKit

/// A button that captures the next key press and records it as a new hotkey shortcut.
///
/// When the user clicks "Record Shortcut", the view enters recording mode and
/// installs an NSEvent local monitor to capture the next key-down event
/// (including modifiers). Pressing Escape cancels recording. Pressing
/// Delete/Backspace resets to the default shortcut.
struct ShortcutRecorderView: View {
    @Binding var configuration: HotkeyConfiguration
    var onUpdate: (HotkeyConfiguration) -> Void

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack {
            Text("Shortcut")
            Spacer()

            if isRecording {
                HStack(spacing: 8) {
                    Text("Press a key…")
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                        .font(.system(.body, design: .monospaced))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(.orange.opacity(0.5), lineWidth: 1)
                        )

                    Button("Cancel") {
                        stopRecording()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            } else {
                Button(action: { startRecording() }) {
                    Text(configuration.displayString)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        .font(.system(.body, design: .monospaced))
                }
                .buttonStyle(.plain)
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                handleFlagsChangedEvent(event)
            } else {
                handleKeyEvent(event)
            }
            return nil // Consume the event
        }
    }

    private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isRecording = false
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Escape cancels recording
        if event.keyCode == 53 {
            stopRecording()
            return
        }

        // Delete/Backspace resets to default
        if event.keyCode == 51 || event.keyCode == 117 {
            var newConfig = HotkeyConfiguration.defaultConfiguration
            newConfig.mode = configuration.mode
            configuration = newConfig
            onUpdate(configuration)
            stopRecording()
            return
        }

        // Build modifier flags
        let relevantModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
        let modifiers = event.modifierFlags.intersection(relevantModifiers)

        var newConfig = configuration
        newConfig.keyCode = event.keyCode
        newConfig.modifierFlags = modifiers.rawValue
        configuration = newConfig
        onUpdate(newConfig)
        stopRecording()
    }

    /// Capture a modifier-only key (like Fn/Globe) as the hotkey.
    /// Only triggers on the press (flag appears), not release.
    private func handleFlagsChangedEvent(_ event: NSEvent) {
        // Only handle modifier-only keys that we recognise.
        let modifierOnlyKeyCodes: Set<UInt16> = [54, 55, 56, 58, 59, 60, 61, 62, 63]
        guard modifierOnlyKeyCodes.contains(event.keyCode) else { return }

        // Fn/Globe (keyCode 63) uses .function flag; others use standard modifier flags.
        let flagForKey: NSEvent.ModifierFlags? = {
            switch event.keyCode {
            case 63: return .function
            case 54, 55: return .command
            case 56, 60: return .shift
            case 58, 61: return .option
            case 59, 62: return .control
            default: return nil
            }
        }()
        guard let flag = flagForKey, event.modifierFlags.contains(flag) else { return }

        // Capture any additional modifiers held alongside the key.
        let relevantModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
        var additionalMods = event.modifierFlags.intersection(relevantModifiers)
        // Remove the modifier flag of the key itself (if it's a standard modifier)
        // so it's not double-counted as both the key and a modifier.
        switch event.keyCode {
        case 54, 55: additionalMods.remove(.command)
        case 56, 60: additionalMods.remove(.shift)
        case 58, 61: additionalMods.remove(.option)
        case 59, 62: additionalMods.remove(.control)
        default: break // Fn (.function) is not in relevantModifiers, nothing to remove
        }

        var newConfig = configuration
        newConfig.keyCode = event.keyCode
        newConfig.modifierFlags = additionalMods.rawValue
        configuration = newConfig
        onUpdate(newConfig)
        stopRecording()
    }
}
