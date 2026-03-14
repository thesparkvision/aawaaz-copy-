import XCTest
@testable import Aawaaz

/// Spike tests for MLX Swift LM integration (Step 3.3).
///
/// These tests validate that MLX Swift LM works for our text cleanup use case.
/// They require network access (first run downloads ~400 MB model from HuggingFace)
/// and take significant time, so they are **opt-in**.
///
/// **From Xcode:**
///   1. Edit the Aawaaz scheme → Test → select the Aawaaz test plan
///   2. Click the ⓘ next to the test plan → Configurations → Default
///   3. Under Environment Variables, enable `RUN_LLM_SPIKE`
///   4. Run the LLMSpikeTests test class from the Test navigator
///
/// **From CLI (two options):**
///
///   Option A — UserDefaults (persistent until cleared):
///   ```
///   defaults write dev.shantanugoel.Aawaaz RUN_LLM_SPIKE -bool YES
///   cd Aawaaz && xcodebuild test -project Aawaaz.xcodeproj -scheme Aawaaz \
///     -configuration Debug -only-testing:AawaazTests/LLMSpikeTests
///   defaults delete dev.shantanugoel.Aawaaz RUN_LLM_SPIKE
///   ```
///
///   Option B — Enable in test plan, run with -testPlan:
///   ```
///   # Edit Aawaaz.xctestplan: set "enabled": true for RUN_LLM_SPIKE
///   cd Aawaaz && xcodebuild test -project Aawaaz.xcodeproj -scheme Aawaaz \
///     -configuration Debug -testPlan Aawaaz -only-testing:AawaazTests/LLMSpikeTests
///   ```
///
/// After the first run, the model is cached in ~/Library/Caches/ and subsequent
/// runs skip the download.
final class LLMSpikeTests: XCTestCase {

    private var skipSpike: Bool {
        // Check environment variable (works from Xcode scheme settings)
        if ProcessInfo.processInfo.environment["RUN_LLM_SPIKE"] == "1" { return false }
        // Check UserDefaults (works from CLI: defaults write dev.shantanugoel.Aawaaz RUN_LLM_SPIKE -bool YES)
        if UserDefaults.standard.bool(forKey: "RUN_LLM_SPIKE") { return false }
        return true
    }

    // MARK: - Full Benchmark

    func testMLXSpikeBenchmark() async throws {
        try XCTSkipIf(skipSpike, "Set RUN_LLM_SPIKE=1 to run the MLX spike benchmark")

        let runner = LLMSpikeRunner()
        let result = try await runner.runBenchmark()

        print(result)

        // Validate the benchmark produced reasonable results
        XCTAssertGreaterThan(result.modelLoadTimeSeconds, 0, "Model load should take measurable time")
        XCTAssertGreaterThan(result.coldInferenceTimeSeconds, 0, "Cold inference should take measurable time")
        XCTAssertGreaterThan(result.warmInferenceTimeSeconds, 0, "Warm inference should take measurable time")
        XCTAssertFalse(result.coldOutput.isEmpty, "Cold inference should produce output")
        XCTAssertFalse(result.warmOutput.isEmpty, "Warm inference should produce output")

        // Spike success criteria (generous bounds — we just want to know it works):
        // - Model load under 30s (first run may be slower due to download — run
        //   once to cache the model, then re-run for representative numbers)
        // - Inference under 10s per call for a 0.6B model
        // - Memory under 2 GB after inference
        XCTAssertLessThan(result.modelLoadTimeSeconds, 30,
            "Model load took \(result.modelLoadTimeSeconds)s — too slow for UX")
        XCTAssertLessThan(result.coldInferenceTimeSeconds, 10,
            "Cold inference took \(result.coldInferenceTimeSeconds)s — too slow for UX")
        XCTAssertLessThan(result.warmInferenceTimeSeconds, 10,
            "Warm inference took \(result.warmInferenceTimeSeconds)s — too slow for UX")
        XCTAssertLessThan(result.memoryAfterInferenceMB, 2048,
            "Memory after inference: \(result.memoryAfterInferenceMB) MB — too high for a 0.6B model")
    }

    // MARK: - Output Quality Check

    func testMLXOutputCleanliness() async throws {
        try XCTSkipIf(skipSpike, "Set RUN_LLM_SPIKE=1 to run the MLX spike tests")

        let runner = LLMSpikeRunner()

        // Test with a filler-heavy input
        let result = try await runner.runBenchmark(
            sampleTexts: [
                "um so like I need to um send an email to um John about the uh project deadline you know",
                "basically what I'm trying to say is that we should um reschedule the meeting to like next week",
            ]
        )

        // The output should be cleaner than the input
        XCTAssertFalse(result.coldOutput.isEmpty, "Cold inference should produce non-empty output")
        let fillerWords = ["um", "uh", "like", "you know", "basically"]
        let coldOutputLower = result.coldOutput.lowercased()

        // Count remaining fillers — the model should remove at least some
        let remainingFillers = fillerWords.filter { coldOutputLower.contains($0) }
        print("[Spike] Remaining fillers in output: \(remainingFillers)")
        print("[Spike] Input:  \(result.coldInput)")
        print("[Spike] Output: \(result.coldOutput)")

        // The model should reduce filler count (doesn't need to be perfect)
        let inputLower = result.coldInput.lowercased()
        let inputFillerCount = fillerWords.reduce(0) { count, filler in
            count + inputLower.components(separatedBy: filler).count - 1
        }
        XCTAssertLessThan(remainingFillers.count, inputFillerCount,
            "Model should remove at least some filler words")

        // The output should not contain thinking tags
        XCTAssertFalse(result.coldOutput.contains("<think>"),
            "Output should not contain <think> tags")
    }

    // MARK: - Thinking Tag Stripping

    func testStripThinkingTags() {
        // This runs without the model — pure string processing
        let cases: [(input: String, expected: String)] = [
            // No tags
            ("Hello world", "Hello world"),
            // Simple thinking tags
            ("<think>Let me think...</think>Hello world", "Hello world"),
            // Multi-line thinking
            ("<think>\nI should clean this up.\nLet me fix grammar.\n</think>\nHello world", "Hello world"),
            // Empty thinking
            ("<think></think>Cleaned text", "Cleaned text"),
            // No content after tags
            ("<think>thinking</think>", ""),
            // Dangling <think> without closing tag (truncated output)
            ("Hello world<think>Let me think about", "Hello world"),
            // Dangling <think> at start
            ("<think>partial thinking", ""),
        ]

        for (input, expected) in cases {
            let result = LLMSpikeRunner.stripThinkingTags(input)
            XCTAssertEqual(result, expected, "Failed for input: \(input)")
        }
    }

    // MARK: - Memory Measurement

    func testMemoryMeasurement() {
        // Validate the memory measurement utility works
        let memoryMB = LLMSpikeRunner.currentMemoryMB()
        XCTAssertGreaterThan(memoryMB, 0, "Memory measurement should return a positive value")
        print("[Spike] Current process memory: \(String(format: "%.1f", memoryMB)) MB")
    }
}
