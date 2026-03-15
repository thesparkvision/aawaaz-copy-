import XCTest
@testable import Aawaaz

final class CleanupLevelTests: XCTestCase {

    // MARK: - CleanupLevel Enum

    func testCleanupLevelRawValues() {
        XCTAssertEqual(CleanupLevel.light.rawValue, "light")
        XCTAssertEqual(CleanupLevel.medium.rawValue, "medium")
        XCTAssertEqual(CleanupLevel.full.rawValue, "full")
    }

    func testCleanupLevelDisplayNames() {
        XCTAssertEqual(CleanupLevel.light.displayName, "Light")
        XCTAssertEqual(CleanupLevel.medium.displayName, "Medium")
        XCTAssertEqual(CleanupLevel.full.displayName, "Full")
    }

    func testCleanupLevelCodable() throws {
        for level in CleanupLevel.allCases {
            let data = try JSONEncoder().encode(level)
            let decoded = try JSONDecoder().decode(CleanupLevel.self, from: data)
            XCTAssertEqual(decoded, level)
        }
    }

    func testCleanupLevelPersistence() {
        let key = "llm.cleanupLevel"
        let savedValue = UserDefaults.standard.string(forKey: key)
        defer {
            if let savedValue {
                UserDefaults.standard.set(savedValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        CleanupLevel.full.save()
        XCTAssertEqual(CleanupLevel.load(), .full)

        CleanupLevel.light.save()
        XCTAssertEqual(CleanupLevel.load(), .light)

        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(CleanupLevel.load(), .medium, "Default should be medium")
    }

    // MARK: - PostProcessingMode Enum

    func testPostProcessingModeRawValues() {
        XCTAssertEqual(PostProcessingMode.off.rawValue, "off")
        XCTAssertEqual(PostProcessingMode.local.rawValue, "local")
    }

    func testPostProcessingModePersistence() {
        let key = "llm.postProcessingMode"
        let savedValue = UserDefaults.standard.string(forKey: key)
        defer {
            if let savedValue {
                UserDefaults.standard.set(savedValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        PostProcessingMode.local.save()
        XCTAssertEqual(PostProcessingMode.load(), .local)

        PostProcessingMode.off.save()
        XCTAssertEqual(PostProcessingMode.load(), .off)

        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(PostProcessingMode.load(), .off, "Default should be off")
    }

    // MARK: - Prompt Construction: Light Level

    func testLightPromptFixesGrammar() {
        let context = InsertionContext(
            appName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            fieldType: .multiLine
        )
        let prompt = LocalLLMProcessor.buildSystemPrompt(for: context, cleanupLevel: .light)

        XCTAssert(prompt.contains("Fix small grammar mistakes"), "Light prompt should fix grammar")
    }

    func testLightPromptDoesNotRemoveFillers() {
        let context = InsertionContext.unknown
        let prompt = LocalLLMProcessor.buildSystemPrompt(for: context, cleanupLevel: .light)

        XCTAssert(prompt.contains("Keep all words the same"), "Light prompt should keep all words unchanged")
    }

    func testLightPromptHasNoCategoryInstruction() {
        let context = InsertionContext(
            appName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            fieldType: .multiLine
        )
        let prompt = LocalLLMProcessor.buildSystemPrompt(for: context, cleanupLevel: .light)

        XCTAssertFalse(prompt.contains("Keep code, symbols"), "Light prompt for chat should not include code instructions")
        XCTAssertFalse(prompt.contains("Keep commands, flags"), "Light prompt for chat should not include terminal instructions")
    }

    func testLightPromptPreservesHindiEnglish() {
        let context = InsertionContext.unknown
        let prompt = LocalLLMProcessor.buildSystemPrompt(for: context, cleanupLevel: .light)

        XCTAssert(prompt.contains("Hindi-English"), "Light prompt should mention Hindi-English")
    }

    // MARK: - Prompt Construction: Medium Level

    func testMediumPromptImprovesStructure() {
        let context = InsertionContext.unknown
        let prompt = LocalLLMProcessor.buildSystemPrompt(for: context, cleanupLevel: .medium)

        XCTAssert(prompt.contains("split run-on sentences"), "Medium prompt should allow splitting run-on sentences")
        XCTAssert(prompt.contains("Capitalize"), "Medium prompt should fix capitalization")
    }

    func testMediumPromptAllowsMoreLatitudeThanLight() {
        let context = InsertionContext.unknown
        let prompt = LocalLLMProcessor.buildSystemPrompt(for: context, cleanupLevel: .medium)

        XCTAssertFalse(prompt.contains("Keep all words the same"), "Medium prompt should not restrict to keeping all words")
        XCTAssert(prompt.contains("Keep the same meaning"), "Medium prompt should preserve meaning")
    }

    func testMediumPromptHasNoCategoryInstruction() {
        let context = InsertionContext(
            appName: "Mail",
            bundleIdentifier: "com.apple.mail",
            fieldType: .multiLine
        )
        let prompt = LocalLLMProcessor.buildSystemPrompt(for: context, cleanupLevel: .medium)

        XCTAssertFalse(prompt.contains("Keep code, symbols"), "Medium prompt for email should not include code instructions")
        XCTAssertFalse(prompt.contains("Keep commands, flags"), "Medium prompt for email should not include terminal instructions")
    }

    // MARK: - Prompt Construction: Full Level

    func testFullPromptAllowsRewriteForClarity() {
        let context = InsertionContext.unknown
        let prompt = LocalLLMProcessor.buildSystemPrompt(for: context, cleanupLevel: .full)

        XCTAssert(prompt.contains("small rewrite only if needed for clarity"), "Full prompt should allow rewrites for clarity")
        XCTAssertFalse(prompt.contains("Keep all words the same"), "Full prompt should not restrict to keeping all words")
    }

    func testFullPromptHasNoSpecialInstructionsForEmail() {
        let context = InsertionContext(
            appName: "Mail",
            bundleIdentifier: "com.apple.mail",
            fieldType: .multiLine
        )
        let prompt = LocalLLMProcessor.buildSystemPrompt(for: context, cleanupLevel: .full)

        XCTAssertFalse(prompt.contains("Keep code, symbols"), "Full prompt for email should not include code instructions")
        XCTAssertFalse(prompt.contains("Keep commands, flags"), "Full prompt for email should not include terminal instructions")
        XCTAssert(prompt.contains("Fix small grammar mistakes"), "Full prompt for email should include base cleanup")
    }

    func testFullPromptHasNoSpecialInstructionsForChat() {
        let context = InsertionContext(
            appName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            fieldType: .multiLine
        )
        let prompt = LocalLLMProcessor.buildSystemPrompt(for: context, cleanupLevel: .full)

        XCTAssertFalse(prompt.contains("Keep code, symbols"), "Full prompt for chat should not include code instructions")
        XCTAssertFalse(prompt.contains("Keep commands, flags"), "Full prompt for chat should not include terminal instructions")
        XCTAssert(prompt.contains("Fix small grammar mistakes"), "Full prompt for chat should include base cleanup")
    }

    func testFullPromptIncludesCodeInstructions() {
        let context = InsertionContext(
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            fieldType: .multiLine
        )
        let prompt = LocalLLMProcessor.buildSystemPrompt(for: context, cleanupLevel: .full)

        XCTAssert(prompt.contains("Keep code, symbols, filenames, APIs, and identifiers exact"), "Full prompt should preserve code identifiers")
        XCTAssert(prompt.contains("Only clean surrounding prose"), "Full prompt should limit cleanup to prose in code editors")
    }

    func testFullPromptIncludesTerminalInstructions() {
        let context = InsertionContext(
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            fieldType: .singleLine
        )
        let prompt = LocalLLMProcessor.buildSystemPrompt(for: context, cleanupLevel: .full)

        XCTAssert(prompt.contains("Keep commands, flags, paths, and casing exact"), "Full prompt should preserve terminal commands")
        XCTAssert(prompt.contains("Only clean surrounding prose"), "Full prompt should limit cleanup to prose in terminal")
    }

    func testFullPromptHasNoSpecialInstructionsForDocument() {
        let context = InsertionContext(
            appName: "Pages",
            bundleIdentifier: "com.apple.iWork.Pages",
            fieldType: .multiLine
        )
        let prompt = LocalLLMProcessor.buildSystemPrompt(for: context, cleanupLevel: .full)

        XCTAssertFalse(prompt.contains("Keep code, symbols"), "Full prompt for document should not include code instructions")
        XCTAssertFalse(prompt.contains("Keep commands, flags"), "Full prompt for document should not include terminal instructions")
        XCTAssert(prompt.contains("Fix small grammar mistakes"), "Full prompt for document should include base cleanup")
    }

    func testFullPromptHasNoSpecialInstructionsForBrowser() {
        let context = InsertionContext(
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            fieldType: .webArea
        )
        let prompt = LocalLLMProcessor.buildSystemPrompt(for: context, cleanupLevel: .full)

        XCTAssertFalse(prompt.contains("Keep code, symbols"), "Full prompt for browser should not include code instructions")
        XCTAssertFalse(prompt.contains("Keep commands, flags"), "Full prompt for browser should not include terminal instructions")
    }

    // MARK: - Field Type Constraints

    func testSingleLineConstraintAtAllLevels() {
        let context = InsertionContext(
            appName: "Spotlight",
            bundleIdentifier: "com.apple.Spotlight",
            fieldType: .singleLine
        )

        for level in CleanupLevel.allCases {
            let prompt = LocalLLMProcessor.buildSystemPrompt(for: context, cleanupLevel: level)
            XCTAssert(
                prompt.contains("Output one line only"),
                "\(level.displayName) prompt should include single-line constraint"
            )
        }
    }

    func testMultiLineHasNoFieldConstraint() {
        let context = InsertionContext(
            appName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            fieldType: .multiLine
        )

        for level in CleanupLevel.allCases {
            let prompt = LocalLLMProcessor.buildSystemPrompt(for: context, cleanupLevel: level)
            XCTAssertFalse(
                prompt.contains("Output one line only"),
                "\(level.displayName) prompt should NOT include single-line constraint for multiLine"
            )
        }
    }

    // MARK: - All Prompts End with Output Instruction

    func testAllPromptsEndWithOutputInstruction() {
        let context = InsertionContext.unknown

        for level in CleanupLevel.allCases {
            let prompt = LocalLLMProcessor.buildSystemPrompt(for: context, cleanupLevel: level)
            XCTAssert(
                prompt.contains("Return only the cleaned text"),
                "\(level.displayName) prompt should include output instruction"
            )
        }
    }

    // MARK: - NoOpProcessor Ignores CleanupLevel

    func testNoOpProcessorReturnsInputUnchanged() async throws {
        let processor = NoOpProcessor()
        let input = "um so like hello world"
        let context = InsertionContext.unknown

        for level in CleanupLevel.allCases {
            let output = try await processor.process(rawText: input, context: context, cleanupLevel: level, scriptPreference: nil)
            XCTAssertEqual(output, input, "NoOpProcessor should return input unchanged at \(level.displayName)")
        }
    }

}
