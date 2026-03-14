import AppKit

/// Hotkey activation mode.
enum HotkeyMode: String, CaseIterable, Identifiable, Codable {
    case hold = "Hold to Talk"
    case toggle = "Toggle"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .hold: return "Hold the shortcut while speaking, release to finish"
        case .toggle: return "Press to start, press again to stop"
        }
    }
}

/// Represents a global keyboard shortcut for activating dictation.
///
/// Stores the key code and modifier flags, and persists them in UserDefaults.
struct HotkeyConfiguration: Codable, Equatable {

    /// The virtual key code (from `CGKeyCode`).
    var keyCode: UInt16

    /// Modifier flags (shift, control, option, command).
    var modifierFlags: UInt

    /// Activation mode (hold or toggle).
    var mode: HotkeyMode

    // MARK: - Defaults

    /// Default shortcut: Fn/Globe key (keyCode 63, no modifiers, hold-to-talk).
    ///
    /// **Note:** On Apple Silicon Macs the Fn key doubles as the Globe key and
    /// may be configured for Dictation, Emoji, or Input Source by default.
    /// Users may need to change System Settings → Keyboard → "Press 🌐 to"
    /// → "Do Nothing" to avoid conflicts.
    ///
    /// Previous default (⌥Space) remains a good alternative for users who
    /// prefer a modifier-key combo.
    static let defaultConfiguration = HotkeyConfiguration(
        keyCode: 63, // Fn / Globe key
        modifierFlags: 0,
        mode: .hold
    )

    /// Whether this hotkey uses a modifier-only key (like Fn/Globe) that
    /// generates `flagsChanged` events instead of `keyDown`/`keyUp`.
    var isModifierOnlyKey: Bool {
        switch keyCode {
        case 54, 55: return true // Right/Left Command
        case 56, 60: return true // Left/Right Shift
        case 58, 61: return true // Left/Right Option
        case 59, 62: return true // Left/Right Control
        case 63:     return true // Fn / Globe
        default:     return false
        }
    }

    // MARK: - Display

    /// Human-readable description of the shortcut.
    var displayString: String {
        // Modifier-only keys like Fn display just the key name
        if isModifierOnlyKey && modifierFlags == 0 {
            return keyCodeDisplayName
        }

        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(keyCodeDisplayName)
        return parts.joined()
    }

    /// Human-readable name for the key code.
    private var keyCodeDisplayName: String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 53: return "Escape"
        case 51: return "Delete"
        case 63: return "🌐 Fn"
        case 54, 55: return "⌘"
        case 56, 60: return "⇧"
        case 58, 61: return "⌥"
        case 59, 62: return "⌃"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            // Try to get a character from the key code
            if let chars = keyCodeToCharacter(keyCode) {
                return chars.uppercased()
            }
            return "Key(\(keyCode))"
        }
    }

    /// Convert a key code to a character string using the current keyboard layout.
    private func keyCodeToCharacter(_ keyCode: UInt16) -> String? {
        // Common key codes for letter keys (US layout)
        let keyMap: [UInt16: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l",
            38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "n", 46: "m", 47: "."
        ]
        return keyMap[keyCode]
    }

    // MARK: - Persistence

    private static let userDefaultsKey = "hotkeyConfiguration"

    /// Load the saved configuration, or return the default.
    static func load() -> HotkeyConfiguration {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let config = try? JSONDecoder().decode(HotkeyConfiguration.self, from: data) else {
            return .defaultConfiguration
        }
        return config
    }

    /// Save the configuration to UserDefaults.
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }

    // MARK: - Matching

    /// Check whether an NSEvent matches this hotkey configuration.
    func matches(_ event: NSEvent) -> Bool {
        guard event.keyCode == keyCode else { return false }

        let relevantModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
        let eventMods = event.modifierFlags.intersection(relevantModifiers)
        let configMods = NSEvent.ModifierFlags(rawValue: modifierFlags).intersection(relevantModifiers)
        return eventMods == configMods
    }
}
