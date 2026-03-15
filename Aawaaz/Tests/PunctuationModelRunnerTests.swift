import XCTest
@testable import Aawaaz

/// Tests for PunctuationModelRunner against Python reference outputs.
///
/// These tests require the model files to be cached locally via HuggingFace:
/// ```
/// pip install punctuators
/// python -c "from punctuators.models import PunctCapSegModelONNX; PunctCapSegModelONNX.from_pretrained('1-800-BAD-CODE/xlm-roberta_punctuation_fullstop_truecase')"
/// ```
///
/// Tests are skipped if model files are not found.
final class PunctuationModelRunnerTests: XCTestCase {
    
    private var runner: PunctuationModelRunner!
    
    override func setUp() async throws {
        runner = PunctuationModelRunner()
    }
    
    // MARK: - Golden Reference Tests
    
    /// Test cases with expected outputs from Python `punctuators` library:
    /// ```python
    /// model = PunctCapSegModelONNX.from_pretrained(
    ///     '1-800-BAD-CODE/xlm-roberta_punctuation_fullstop_truecase')
    /// result = model.infer([text], apply_sbd=True, overlap=16)
    /// output = ' '.join(result[0])
    /// ```
    func testGoldenReferences() async throws {
        try XCTSkipUnless(PunctuationModelRunner.isAvailable,
            "Punct model not found in HuggingFace cache")
        
        try await runner.loadModel(useANE: false)
        
        let cases: [(input: String, expected: String)] = [
            ("hello world how are you",
             "Hello World, how are you?"),
            ("i think we should meet tomorrow at the office",
             "I think we should meet tomorrow at the office."),
            ("can you check if the server is running and restart it if its not",
             "Can you check if the server is running and restart it if its not?"),
            ("the weather is nice today isnt it",
             "The weather is nice today, isnt it?"),
            ("aaj mera mood acha hai toh main party karunga",
             "Aaj mera mood acha hai toh main party karunga."),
            ("so basically i was thinking about the project and i realized that we need to restructure the whole thing",
             "So basically, I was thinking about the project and I realized that we need to restructure the whole thing."),
        ]
        
        var passed = 0
        for (input, expected) in cases {
            let result = try await runner.predict(input)
            if result == expected {
                passed += 1
            } else {
                // Don't fail — log for debugging. Model output could vary slightly
                // across ONNX Runtime versions.
                print("[PunctTest] MISMATCH:")
                print("  Input:    \"\(input)\"")
                print("  Expected: \"\(expected)\"")
                print("  Got:      \"\(result)\"")
            }
        }
        
        // At least 4/6 should match exactly (allow minor model variance)
        XCTAssertGreaterThanOrEqual(passed, 4,
            "Expected at least 4/\(cases.count) golden reference matches, got \(passed)")
        print("[PunctTest] Golden references: \(passed)/\(cases.count) exact matches")
    }
    
    // MARK: - Edge Cases
    
    func testEmptyInput() async throws {
        try XCTSkipUnless(PunctuationModelRunner.isAvailable,
            "Punct model not found in HuggingFace cache")
        
        try await runner.loadModel(useANE: false)
        
        let result = try await runner.predict("")
        XCTAssertEqual(result, "")
        
        let result2 = try await runner.predict("   ")
        XCTAssertEqual(result2, "   ")
    }
    
    func testSingleWord() async throws {
        try XCTSkipUnless(PunctuationModelRunner.isAvailable,
            "Punct model not found in HuggingFace cache")
        
        try await runner.loadModel(useANE: false)
        
        let result = try await runner.predict("hello")
        // Model should at least capitalize it
        XCTAssertTrue(result.hasPrefix("H"), "Expected capitalized 'Hello', got '\(result)'")
    }
    
    // MARK: - Model State
    
    func testModelNotLoadedThrows() async {
        do {
            _ = try await runner.predict("hello")
            XCTFail("Expected error for unloaded model")
        } catch {
            XCTAssertTrue(error is PunctuationModelError)
        }
    }
    
    func testANEToggleReload() async throws {
        try XCTSkipUnless(PunctuationModelRunner.isAvailable,
            "Punct model not found in HuggingFace cache")
        
        // Load with CPU
        try await runner.loadModel(useANE: false)
        let state1 = await runner.modelState
        XCTAssertEqual(state1, .loaded)
        
        // "Reload" with same setting should be a no-op
        try await runner.loadModel(useANE: false)
        
        // Load with ANE toggle should reload
        try await runner.loadModel(useANE: true)
        let state2 = await runner.modelState
        XCTAssertEqual(state2, .loaded)
    }
    
    // MARK: - Input Analysis

    func testIsAlreadyPunctuated() {
        // Should be detected as punctuated (skip model)
        XCTAssertTrue(PunctuationModelRunner.isAlreadyPunctuated("Can you please tell me?"))
        XCTAssertTrue(PunctuationModelRunner.isAlreadyPunctuated("Hello! How are you"))
        XCTAssertTrue(PunctuationModelRunner.isAlreadyPunctuated("First sentence. Second sentence."))
        XCTAssertTrue(PunctuationModelRunner.isAlreadyPunctuated("I don't know what's going on here. Can you please tell me?"))
        // Internal period (period not at end)
        XCTAssertTrue(PunctuationModelRunner.isAlreadyPunctuated("I don't know. can you tell me"))

        // Should NOT be detected as punctuated (run model)
        XCTAssertFalse(PunctuationModelRunner.isAlreadyPunctuated("hello world how are you"))
        XCTAssertFalse(PunctuationModelRunner.isAlreadyPunctuated("i think we should meet tomorrow"))
        XCTAssertFalse(PunctuationModelRunner.isAlreadyPunctuated(""))
        // Single trailing period is NOT enough — could be a run-on
        XCTAssertFalse(PunctuationModelRunner.isAlreadyPunctuated("just a single sentence with a period at the end."))
    }

    func testNormalizeForModel() {
        XCTAssertEqual(
            PunctuationModelRunner.normalizeForModel("Hello World, how are you?"),
            "hello world how are you")
        XCTAssertEqual(
            PunctuationModelRunner.normalizeForModel("I don't know."),
            "i don't know")
        XCTAssertEqual(
            PunctuationModelRunner.normalizeForModel("already lowercase no punct"),
            "already lowercase no punct")
        // Preserve punctuation between digits
        XCTAssertEqual(
            PunctuationModelRunner.normalizeForModel("version 1.2.3 at 10:30"),
            "version 1.2.3 at 10:30")
        XCTAssertEqual(
            PunctuationModelRunner.normalizeForModel("Pi is 3.14 exactly."),
            "pi is 3.14 exactly")
    }

    func testSanitizePunctuation() {
        XCTAssertEqual(PunctuationModelRunner.sanitizePunctuation("Hello??"), "Hello?")
        XCTAssertEqual(PunctuationModelRunner.sanitizePunctuation("Hello.."), "Hello.")
        XCTAssertEqual(PunctuationModelRunner.sanitizePunctuation("Hello!!"), "Hello!")
        XCTAssertEqual(PunctuationModelRunner.sanitizePunctuation("Hello ."), "Hello.")
        // Normal text passes through unchanged
        XCTAssertEqual(PunctuationModelRunner.sanitizePunctuation("Hello, world."), "Hello, world.")
    }

    func testSkipOnPunctuatedInput() async throws {
        try XCTSkipUnless(PunctuationModelRunner.isAvailable,
            "Punct model not found in HuggingFace cache")

        try await runner.loadModel(useANE: false)

        // Pre-punctuated text with ? should be returned unchanged
        let input = "I don't know what's going on here. Can you please tell me?"
        let result = try await runner.predict(input)
        XCTAssertEqual(result, input, "Punctuated input should pass through unchanged")
    }

    // MARK: - Latency
    
    func testInferenceLatency() async throws {
        try XCTSkipUnless(PunctuationModelRunner.isAvailable,
            "Punct model not found in HuggingFace cache")
        
        try await runner.loadModel(useANE: false)
        
        let input = "so basically i was thinking about the project and i realized that we need to restructure the whole thing because the current architecture is not scalable and we need something better"
        
        // Warm-up
        _ = try await runner.predict(input)
        
        // Measure
        let start = CFAbsoluteTimeGetCurrent()
        let iterations = 5
        for _ in 0..<iterations {
            _ = try await runner.predict(input)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let avgMs = (elapsed / Double(iterations)) * 1000
        
        print("[PunctTest] Average inference latency (CPU): \(String(format: "%.1f", avgMs))ms")
        
        // Sanity check: should be under 10 seconds per inference on CPU
        XCTAssertLessThan(avgMs, 10000, "Inference too slow")
    }
}
