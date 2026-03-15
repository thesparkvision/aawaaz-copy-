import AppKit

/// Describes the context in which text will be inserted: the target application,
/// the kind of text field, and any per-app insertion preferences.
///
/// Passed downstream to post-processing (Phase 3) for context-aware formatting.
struct InsertionContext: Sendable {

    /// The frontmost application's display name (e.g. "Safari", "VS Code").
    let appName: String

    /// The frontmost application's bundle identifier (e.g. "com.apple.Safari").
    let bundleIdentifier: String

    /// The kind of text element that is focused.
    let fieldType: TextFieldType

    /// The insertion method that was actually used.
    var insertionMethod: InsertionMethod = .accessibility

    /// Up to ~200 characters of text preceding the cursor in the focused field.
    /// Used by the LLM to infer continuity, capitalization, and tone.
    /// `nil` when the field is secure, unreadable, or AX permission is missing.
    var surroundingText: String? = nil

    /// Describes the kind of focused text element.
    enum TextFieldType: String, Codable, Sendable {
        case singleLine   // AXTextField
        case multiLine    // AXTextArea
        case comboBox     // AXComboBox
        case webArea      // AXWebArea (browser content editable)
        case unknown
    }

    /// Which insertion strategy was used for this insertion.
    enum InsertionMethod: String, Codable, Sendable {
        case accessibility
        case keystrokeSimulation
        case clipboardOnly
    }

    /// High-level category of the target application, used by post-processors
    /// to tailor tone and formatting (e.g., formal for email, casual for chat).
    ///
    /// Determined automatically from the app's bundle identifier via
    /// ``bundleIDToCategory``. Users can override per-app in settings
    /// (Step 3.5.7).
    enum AppCategory: String, Codable, CaseIterable, Sendable {
        case email
        case chat
        case document
        case code
        case terminal
        case browser
        case other
    }

    /// Known bundle-ID → category mappings.
    ///
    /// Used by ``appCategory`` to infer the category automatically.
    /// User overrides (stored in UserDefaults, Step 3.5.7) take precedence.
    static let bundleIDToCategory: [String: AppCategory] = [
        // Email
        "com.apple.mail": .email,
        "com.microsoft.Outlook": .email,
        // Chat / Messaging
        "com.tinyspeck.slackmacgap": .chat,
        "com.apple.MobileSMS": .chat,
        "com.hnc.Discord": .chat,
        "com.electron.whatsapp": .chat,
        "ru.keepcoder.Telegram": .chat,
        "com.facebook.archon": .chat,
        // Documents
        "com.microsoft.Word": .document,
        "com.apple.iWork.Pages": .document,
        "com.apple.TextEdit": .document,
        "com.apple.Notes": .document,
        "md.obsidian": .document,
        "notion.id": .document,
        // Code editors
        "com.apple.dt.Xcode": .code,
        "com.microsoft.VSCode": .code,
        "com.sublimetext.4": .code,
        // Terminal
        "com.googlecode.iterm2": .terminal,
        "com.apple.Terminal": .terminal,
        "dev.warp.Warp-Stable": .terminal,
        // Browsers
        "com.apple.Safari": .browser,
        "com.google.Chrome": .browser,
        "org.mozilla.firefox": .browser,
        "com.brave.Browser": .browser,
        "com.microsoft.edgemac": .browser,
        "company.thebrowser.Browser": .browser,
    ]

    /// Bundle ID prefixes that map to categories, checked when no exact
    /// match exists in ``bundleIDToCategory``.
    private static let prefixToCategory: [(String, AppCategory)] = [
        ("com.jetbrains.", .code),
    ]

    /// The inferred category for this app based on its bundle identifier.
    ///
    /// Resolution order:
    /// 1. User override (stored in UserDefaults, Step 3.5.7)
    /// 2. Exact match in ``bundleIDToCategory``
    /// 3. Prefix match in ``prefixToCategory``
    /// 4. `.other`
    var appCategory: AppCategory {
        // 1. User override
        let overrideKey = "appCategory.\(bundleIdentifier)"
        if let override = UserDefaults.standard.string(forKey: overrideKey),
           let category = AppCategory(rawValue: override) {
            return category
        }

        // 2. Exact match
        if let category = Self.bundleIDToCategory[bundleIdentifier] {
            return category
        }

        // 3. Prefix match
        for (prefix, category) in Self.prefixToCategory {
            if bundleIdentifier.hasPrefix(prefix) {
                return category
            }
        }

        return .other
    }

    /// A fallback context used when the frontmost app cannot be determined.
    static let unknown = InsertionContext(
        appName: "Unknown",
        bundleIdentifier: "",
        fieldType: .unknown
    )

    /// Build an `InsertionContext` from the currently focused element.
    ///
    /// Returns `nil` if no frontmost application can be determined.
    ///
    /// - Parameter captureSurrounding: Whether to read text before the cursor from the
    ///   focused field. Defaults to `false` for lightweight metadata-only queries.
    ///   Pass `true` only when the context will be used for LLM prompt injection.
    ///
    /// - Note: Uses `NSWorkspace` and Accessibility APIs — should be called
    ///   from the main thread. Consider adding `@MainActor` in a future
    ///   concurrency audit.
    static func current(captureSurrounding: Bool = false) -> InsertionContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }

        let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        let bundleID = app.bundleIdentifier ?? ""

        // Share the focused element lookup between field type detection and
        // surrounding text capture to avoid redundant AX queries.
        let focusedElement = getFocusedElement(for: app)
        let fieldType = focusedElement.map { detectFieldType(from: $0) } ?? .unknown
        let surrounding = captureSurrounding
            ? focusedElement.flatMap { captureSurroundingText(from: $0) }
            : nil

        return InsertionContext(
            appName: appName,
            bundleIdentifier: bundleID,
            fieldType: fieldType,
            surroundingText: surrounding
        )
    }

    // MARK: - AX Element Helpers

    /// Get the focused UI element for the given application.
    private static func getFocusedElement(for app: NSRunningApplication) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focusedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard result == .success,
              let ref = focusedRef,
              CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    /// Detect the text field type from an already-resolved AX element.
    private static func detectFieldType(from element: AXUIElement) -> TextFieldType {
        var roleRef: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleRef
        )
        guard roleResult == .success, let role = roleRef as? String else {
            return .unknown
        }

        switch role {
        case kAXTextFieldRole:  return .singleLine
        case kAXTextAreaRole:   return .multiLine
        case kAXComboBoxRole:   return .comboBox
        case "AXWebArea":       return .webArea
        default:                return .unknown
        }
    }

    // MARK: - Surrounding Text Capture

    /// Maximum number of characters to capture before the cursor.
    private static let maxSurroundingChars = 200

    /// Capture up to ~200 characters of text before the cursor from the focused element.
    ///
    /// Fails closed: returns `nil` if the element is secure or the value/range cannot be read.
    private static func captureSurroundingText(from element: AXUIElement) -> String? {
        // Fail closed: refuse to read from secure text fields
        if isSecureField(element) { return nil }

        // Read the full text value
        var valueRef: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            element, kAXValueAttribute as CFString, &valueRef
        )
        guard valueResult == .success, let fullText = valueRef as? String,
              !fullText.isEmpty else { return nil }

        // Read the selected text range to find cursor position
        var rangeRef: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeRef
        )
        guard rangeResult == .success, let axValue = rangeRef else { return nil }

        var cfRange = CFRange(location: 0, length: 0)
        // AXValue is a CF type — the cast always succeeds for range attributes.
        guard AXValueGetValue(axValue as! AXValue, .cfRange, &cfRange) else { return nil }

        let nsText = fullText as NSString
        let cursorPos = cfRange.location
        guard cursorPos > 0, cursorPos <= nsText.length else { return nil }

        let start = max(0, cursorPos - maxSurroundingChars)
        let length = cursorPos - start
        let range = NSRange(location: start, length: length)

        let captured = nsText.substring(with: range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return captured.isEmpty ? nil : captured
    }

    /// Check if the focused AX element is a secure (password) field.
    ///
    /// Fail-closed: returns `true` (secure) if the role cannot be determined,
    /// so we never read from ambiguous fields.
    private static func isSecureField(_ element: AXUIElement) -> Bool {
        // Check AXSubrole for AXSecureTextField
        var subroleRef: CFTypeRef?
        let subroleResult = AXUIElementCopyAttributeValue(
            element, kAXSubroleAttribute as CFString, &subroleRef
        )
        if subroleResult == .success, let subrole = subroleRef as? String,
           subrole == "AXSecureTextField" {
            return true
        }

        // Check AXRole — if we can't read it, assume secure (fail closed)
        var roleRef: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(
            element, kAXRoleAttribute as CFString, &roleRef
        )
        guard roleResult == .success, let role = roleRef as? String else {
            return true // Can't determine role → treat as secure
        }

        return role == "AXSecureTextField"
    }
}
