import XCTest
@testable import Aawaaz

final class LocalLLMProcessorTests: XCTestCase {

    // MARK: - capitalizeStartIfAppropriate

    func testCapitalizesProseLowercaseStart() {
        let ctx = InsertionContext(appName: "Notes", bundleIdentifier: "com.apple.Notes", fieldType: .multiLine)
        XCTAssertEqual(
            LocalLLMProcessor.capitalizeStartIfAppropriate("this is a test.", context: ctx),
            "This is a test."
        )
    }

    func testSkipsAlreadyCapitalized() {
        let ctx = InsertionContext(appName: "Notes", bundleIdentifier: "com.apple.Notes", fieldType: .multiLine)
        XCTAssertEqual(
            LocalLLMProcessor.capitalizeStartIfAppropriate("Already capitalized.", context: ctx),
            "Already capitalized."
        )
    }

    func testSkipsCodeContext() {
        let ctx = InsertionContext(appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", fieldType: .multiLine)
        XCTAssertEqual(
            LocalLLMProcessor.capitalizeStartIfAppropriate("let x = 42", context: ctx),
            "let x = 42"
        )
    }

    func testSkipsTerminalContext() {
        let ctx = InsertionContext(appName: "Terminal", bundleIdentifier: "com.apple.Terminal", fieldType: .multiLine)
        XCTAssertEqual(
            LocalLLMProcessor.capitalizeStartIfAppropriate("git status", context: ctx),
            "git status"
        )
    }

    func testSkipsURL() {
        let ctx = InsertionContext(appName: "Safari", bundleIdentifier: "com.apple.Safari", fieldType: .singleLine)
        XCTAssertEqual(
            LocalLLMProcessor.capitalizeStartIfAppropriate("https://example.com/path", context: ctx),
            "https://example.com/path"
        )
    }

    func testSkipsAbsolutePath() {
        let ctx = InsertionContext(appName: "Notes", bundleIdentifier: "com.apple.Notes", fieldType: .multiLine)
        XCTAssertEqual(
            LocalLLMProcessor.capitalizeStartIfAppropriate("/usr/local/bin", context: ctx),
            "/usr/local/bin"
        )
    }

    func testSkipsHomePath() {
        let ctx = InsertionContext(appName: "Notes", bundleIdentifier: "com.apple.Notes", fieldType: .multiLine)
        XCTAssertEqual(
            LocalLLMProcessor.capitalizeStartIfAppropriate("~/Documents/file.txt", context: ctx),
            "~/Documents/file.txt"
        )
    }

    func testSkipsCLIFlag() {
        let ctx = InsertionContext(appName: "Notes", bundleIdentifier: "com.apple.Notes", fieldType: .multiLine)
        XCTAssertEqual(
            LocalLLMProcessor.capitalizeStartIfAppropriate("--force", context: ctx),
            "--force"
        )
    }

    func testSkipsHandle() {
        let ctx = InsertionContext(appName: "Notes", bundleIdentifier: "com.apple.Notes", fieldType: .multiLine)
        XCTAssertEqual(
            LocalLLMProcessor.capitalizeStartIfAppropriate("@admin check this", context: ctx),
            "@admin check this"
        )
    }

    func testSkipsEmail() {
        let ctx = InsertionContext(appName: "Notes", bundleIdentifier: "com.apple.Notes", fieldType: .multiLine)
        XCTAssertEqual(
            LocalLLMProcessor.capitalizeStartIfAppropriate("john@example.com", context: ctx),
            "john@example.com"
        )
    }

    func testCapitalizesSingleLineField() {
        let ctx = InsertionContext(appName: "Safari", bundleIdentifier: "com.apple.Safari", fieldType: .singleLine)
        XCTAssertEqual(
            LocalLLMProcessor.capitalizeStartIfAppropriate("search for restaurants", context: ctx),
            "Search for restaurants"
        )
    }

    func testCapitalizesWwwSkipped() {
        let ctx = InsertionContext(appName: "Safari", bundleIdentifier: "com.apple.Safari", fieldType: .singleLine)
        XCTAssertEqual(
            LocalLLMProcessor.capitalizeStartIfAppropriate("www.example.com", context: ctx),
            "www.example.com"
        )
    }
}
