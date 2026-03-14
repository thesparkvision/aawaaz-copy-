import Foundation

/// How aggressively the LLM cleans up dictated text.
///
/// Controls which instructions appear in the system prompt sent to
/// ``LocalLLMProcessor``. Higher levels do more reformatting but may
/// change the speaker's voice more noticeably.
///
/// - ``light``: Grammar and punctuation only. No restructuring, no
///   filler removal, no tone adjustment.
/// - ``medium``: Adds sentence-structure fixes, capitalization, and
///   self-correction resolution.
/// - ``full``: Adds context-aware formatting (email → formal,
///   chat → casual, etc.) and nuanced filler removal.
enum CleanupLevel: String, CaseIterable, Identifiable, Codable, Sendable {
    case light
    case medium
    case full

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light:  return "Light"
        case .medium: return "Medium"
        case .full:   return "Full"
        }
    }

    var description: String {
        switch self {
        case .light:
            return "Grammar and punctuation only"
        case .medium:
            return "Grammar, sentence structure, capitalization"
        case .full:
            return "Full cleanup with context-aware formatting"
        }
    }

    // MARK: - Persistence

    private static let defaultsKey = "llm.cleanupLevel"

    static func load() -> CleanupLevel {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let level = CleanupLevel(rawValue: raw) else {
            return .medium
        }
        return level
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}
