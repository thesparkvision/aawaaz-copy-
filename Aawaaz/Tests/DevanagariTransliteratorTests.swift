import XCTest
@testable import Aawaaz

final class DevanagariTransliteratorTests: XCTestCase {

    private let transliterator = DevanagariTransliterator()

    // MARK: - Basic Vowels

    func testIndependentVowels() {
        XCTAssertEqual(transliterator.transliterate("अ"), "a")
        XCTAssertEqual(transliterator.transliterate("आ"), "aa")
        XCTAssertEqual(transliterator.transliterate("इ"), "i")
        XCTAssertEqual(transliterator.transliterate("ई"), "ee")
        XCTAssertEqual(transliterator.transliterate("उ"), "u")
        XCTAssertEqual(transliterator.transliterate("ऊ"), "oo")
        XCTAssertEqual(transliterator.transliterate("ए"), "e")
        XCTAssertEqual(transliterator.transliterate("ऐ"), "ai")
        XCTAssertEqual(transliterator.transliterate("ओ"), "o")
        XCTAssertEqual(transliterator.transliterate("औ"), "au")
    }

    // MARK: - Basic Consonants

    func testSimpleConsonants() {
        XCTAssertEqual(transliterator.transliterate("क"), "ka")
        XCTAssertEqual(transliterator.transliterate("ग"), "ga")
        XCTAssertEqual(transliterator.transliterate("म"), "ma")
        XCTAssertEqual(transliterator.transliterate("न"), "na")
        XCTAssertEqual(transliterator.transliterate("ह"), "ha")
    }

    // MARK: - Consonant + Matra

    func testConsonantWithMatra() {
        // कि = k + i-matra
        XCTAssertEqual(transliterator.transliterate("कि"), "ki")
        // की = k + ee-matra
        XCTAssertEqual(transliterator.transliterate("की"), "kee")
        // कु = k + u-matra
        XCTAssertEqual(transliterator.transliterate("कु"), "ku")
        // को = k + o-matra
        XCTAssertEqual(transliterator.transliterate("को"), "ko")
        // का = k + aa-matra
        XCTAssertEqual(transliterator.transliterate("का"), "kaa")
    }

    // MARK: - Virama (Halant)

    func testConsonantWithVirama() {
        // क् = k (halant suppresses inherent "a")
        XCTAssertEqual(transliterator.transliterate("क्"), "k")
    }

    func testConjuncts() {
        // क्या = k + virama + ya + aa-matra
        XCTAssertEqual(transliterator.transliterate("क्या"), "kyaa")
        // स्त = s + virama + ta
        XCTAssertEqual(transliterator.transliterate("स्त"), "sta")
    }

    // MARK: - Common Words

    func testNamaste() {
        // नमस्ते = na + ma + s + te
        XCTAssertEqual(transliterator.transliterate("नमस्ते"), "namaste")
    }

    func testKitaab() {
        // किताब = ki + taa + ba
        XCTAssertEqual(transliterator.transliterate("किताब"), "kitaaba")
        // Note: inherent "a" at word-end is kept (schwa deletion not implemented)
    }

    func testBhaarat() {
        // भारत = bhaa + ra + ta
        XCTAssertEqual(transliterator.transliterate("भारत"), "bhaarata")
    }

    func testHindi() {
        // हिन्दी = hi + n + dee
        XCTAssertEqual(transliterator.transliterate("हिन्दी"), "hindee")
    }

    // MARK: - Anusvara and Chandrabindu

    func testAnusvara() {
        // हैं = hai + anusvara
        XCTAssertEqual(transliterator.transliterate("हैं"), "hain")
        // मैं = mai + anusvara
        XCTAssertEqual(transliterator.transliterate("मैं"), "main")
    }

    func testChandrabindu() {
        // हूँ = hoo + chandrabindu
        XCTAssertEqual(transliterator.transliterate("हूँ"), "hoon")
    }

    // MARK: - Nukta Forms

    func testNuktaForms() {
        // फ़ोन = f + o + na (nukta modifies फ to f)
        XCTAssertEqual(transliterator.transliterate("फ़ोन"), "fona")
        // ज़रा = z + ra + aa (nukta modifies ज to z)
        XCTAssertEqual(transliterator.transliterate("ज़रा"), "zaraa")
    }

    // MARK: - Numerals

    func testDevanagariNumerals() {
        XCTAssertEqual(transliterator.transliterate("१२३"), "123")
        XCTAssertEqual(transliterator.transliterate("०"), "0")
        XCTAssertEqual(transliterator.transliterate("९"), "9")
    }

    // MARK: - Mixed Hindi/English

    func testMixedText() {
        let input = "मुझे meeting schedule करनी है"
        let output = transliterator.transliterate(input)
        // Should transliterate Devanagari and pass through English
        XCTAssertTrue(output.contains("meeting"))
        XCTAssertTrue(output.contains("schedule"))
        XCTAssertFalse(transliterator.containsDevanagari(output))
    }

    // MARK: - Latin Passthrough

    func testLatinPassthrough() {
        let input = "Hello World 123"
        XCTAssertEqual(transliterator.transliterate(input), input)
    }

    func testEmptyString() {
        XCTAssertEqual(transliterator.transliterate(""), "")
    }

    func testPunctuationPreserved() {
        let input = "नमस्ते! कैसे हो?"
        let output = transliterator.transliterate(input)
        XCTAssertTrue(output.contains("!"))
        XCTAssertTrue(output.contains("?"))
    }

    // MARK: - containsDevanagari

    func testContainsDevanagari() {
        XCTAssertTrue(transliterator.containsDevanagari("नमस्ते"))
        XCTAssertTrue(transliterator.containsDevanagari("Hello नमस्ते"))
        XCTAssertFalse(transliterator.containsDevanagari("Hello World"))
        XCTAssertFalse(transliterator.containsDevanagari(""))
    }
}
