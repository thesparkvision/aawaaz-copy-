import Foundation

/// Whether and how post-processing is applied after transcription.
///
/// Controls which ``PostProcessor`` the ``TranscriptionPipeline`` uses:
/// - ``off``: ``NoOpProcessor`` (text passes through unchanged).
/// - ``local``: ``LocalLLMProcessor`` (on-device LLM cleanup via MLX).
///
/// Remote LLM support (Step 3.4) will add a `.remote` case in the future.
enum PostProcessingMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case off
    case local

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:   return "Off"
        case .local: return "Local LLM"
        }
    }

    // MARK: - Persistence

    private static let defaultsKey = "llm.postProcessingMode"

    static func load() -> PostProcessingMode {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let mode = PostProcessingMode(rawValue: raw) else {
            return .off
        }
        return mode
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}
