import Foundation

/// A post-processing step that transforms transcribed text before insertion.
///
/// Post-processors run after Whisper transcription and the deterministic
/// text cleanup pipeline (filler removal, self-correction detection).
/// They receive an ``InsertionContext`` for app-aware formatting and a
/// ``CleanupLevel`` that controls how aggressively text is cleaned.
///
/// Conforming types include:
/// - ``NoOpProcessor``: Pass-through (when post-processing is disabled)
/// - ``LocalLLMProcessor``: On-device LLM cleanup via MLX (Step 3.3)
protocol PostProcessor: Sendable {

    /// Process transcribed text using insertion context and cleanup level.
    ///
    /// - Parameters:
    ///   - rawText: Text to process (output of the deterministic pipeline).
    ///   - context: The insertion context describing the target app and field.
    ///   - cleanupLevel: How aggressively to clean up the text.
    ///   - scriptPreference: Hinglish script preference (romanized/devanagari/mixed), if applicable.
    /// - Returns: Processed text ready for insertion or further processing.
    /// - Throws: If processing fails (callers should fall back to the original text).
    func process(rawText: String, context: InsertionContext, cleanupLevel: CleanupLevel, scriptPreference: HinglishScript?) async throws -> String
}
