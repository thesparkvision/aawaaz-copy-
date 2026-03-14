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
        // Only handle Fn/Globe key (keyCode 63) as a standalone hotkey.
        // Other modifier keys (Shift, Ctrl, etc.) are captured as part of
        // a key combination via handleKeyEvent instead.
        guard event.keyCode == 63,
              event.modifierFlags.contains(.function) else { return }

        var newConfig = configuration
        newConfig.keyCode = 63
        newConfig.modifierFlags = 0
        configuration = newConfig
        onUpdate(newConfig)
        stopRecording()
    }
}
