import Foundation

/// Basic Devanagari → Roman transliteration for use when LLM post-processing is off.
///
/// Uses a simplified ITRANS-inspired mapping that covers the most common
/// Devanagari characters. This is a best-effort transliteration — the LLM
/// path produces higher-quality results for mixed Hindi/English text.
///
/// Iterates over **Unicode scalars** (not `Character`s) so that Devanagari
/// combining sequences (consonant+matra, consonant+virama, nukta forms)
/// are handled correctly. Swift's `Character` groups these into extended
/// grapheme clusters, which would prevent individual component lookups.
///
/// Only processes Devanagari Unicode scalars (U+0900–U+097F); Latin
/// text passes through unchanged.
struct DevanagariTransliterator {

    // MARK: - Vowels (independent forms)

    private static let vowels: [UInt32: String] = [
        0x0905: "a",     // अ
        0x0906: "aa",    // आ
        0x0907: "i",     // इ
        0x0908: "ee",    // ई
        0x0909: "u",     // उ
        0x090A: "oo",    // ऊ
        0x090B: "ri",    // ऋ
        0x090F: "e",     // ए
        0x0910: "ai",    // ऐ
        0x0913: "o",     // ओ
        0x0914: "au",    // औ
    ]

    // MARK: - Vowel signs (matras — combine with preceding consonant)

    private static let matras: [UInt32: String] = [
        0x093E: "aa",    // ा
        0x093F: "i",     // ि
        0x0940: "ee",    // ी
        0x0941: "u",     // ु
        0x0942: "oo",    // ू
        0x0943: "ri",    // ृ
        0x0947: "e",     // े
        0x0948: "ai",    // ै
        0x094B: "o",     // ो
        0x094C: "au",    // ौ
    ]

    // MARK: - Consonants

    private static let consonants: [UInt32: String] = [
        // Velars
        0x0915: "ka",    // क
        0x0916: "kha",   // ख
        0x0917: "ga",    // ग
        0x0918: "gha",   // घ
        0x0919: "nga",   // ङ
        // Palatals
        0x091A: "cha",   // च
        0x091B: "chha",  // छ
        0x091C: "ja",    // ज
        0x091D: "jha",   // झ
        0x091E: "nya",   // ञ
        // Retroflex
        0x091F: "ta",    // ट
        0x0920: "tha",   // ठ
        0x0921: "da",    // ड
        0x0922: "dha",   // ढ
        0x0923: "na",    // ण
        // Dental
        0x0924: "ta",    // त
        0x0925: "tha",   // थ
        0x0926: "da",    // द
        0x0927: "dha",   // ध
        0x0928: "na",    // न
        // Labials
        0x092A: "pa",    // प
        0x092B: "pha",   // फ
        0x092C: "ba",    // ब
        0x092D: "bha",   // भ
        0x092E: "ma",    // म
        // Semi-vowels
        0x092F: "ya",    // य
        0x0930: "ra",    // र
        0x0932: "la",    // ल
        0x0935: "va",    // व
        // Sibilants
        0x0936: "sha",   // श
        0x0937: "sha",   // ष
        0x0938: "sa",    // स
        // Aspirate
        0x0939: "ha",    // ह
    ]

    /// Consonant roots (without trailing inherent "a") for matra suppression.
    private static let consonantRoots: [UInt32: String] = {
        var roots: [UInt32: String] = [:]
        for (scalar, roman) in consonants {
            if roman.hasSuffix("a") {
                roots[scalar] = String(roman.dropLast())
            } else {
                roots[scalar] = roman
            }
        }
        return roots
    }()

    // MARK: - Special scalar values

    private static let virama: UInt32 = 0x094D      // ्  (halant)
    private static let anusvara: UInt32 = 0x0902     // ं
    private static let visarga: UInt32 = 0x0903      // ः
    private static let chandrabindu: UInt32 = 0x0901  // ँ
    private static let nukta: UInt32 = 0x093C         // ़

    // MARK: - Devanagari numerals

    private static let numerals: [UInt32: Character] = [
        0x0966: "0",  // ०
        0x0967: "1",  // १
        0x0968: "2",  // २
        0x0969: "3",  // ३
        0x096A: "4",  // ४
        0x096B: "5",  // ५
        0x096C: "6",  // ६
        0x096D: "7",  // ७
        0x096E: "8",  // ८
        0x096F: "9",  // ९
    ]

    /// Nukta-modified consonant overrides (e.g. फ़ → fa, ज़ → za).
    private static let nuktaOverrides: [UInt32: String] = [
        0x092B: "f",   // फ + nukta → fa
        0x091C: "z",   // ज + nukta → za
        0x0921: "d",   // ड + nukta → da (ड़)
        0x0922: "dh",  // ढ + nukta → dha (ढ़)
        0x0915: "q",   // क + nukta → qa (क़)
        0x0916: "kh",  // ख + nukta → kha (ख़)
        0x0917: "gh",  // ग + nukta → gha (ग़)
    ]

    // MARK: - Public API

    /// Transliterate Devanagari text to Roman/Latin script.
    ///
    /// Non-Devanagari characters (Latin, punctuation, spaces) pass through unchanged.
    /// Mixed Hindi/English text is handled naturally.
    func transliterate(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var result = ""
        var i = 0

        while i < scalars.count {
            let sv = scalars[i].value

            // Devanagari numeral
            if let roman = Self.numerals[sv] {
                result.append(roman)
                i += 1
                continue
            }

            // Independent vowel
            if let romanVowel = Self.vowels[sv] {
                result.append(romanVowel)
                i += 1
                i = appendModifiers(scalars: scalars, index: i, result: &result)
                continue
            }

            // Consonant
            if Self.consonants[sv] != nil {
                // Check for nukta following the consonant
                let hasNukta = (i + 1 < scalars.count && scalars[i + 1].value == Self.nukta)
                let root: String
                if hasNukta, let override = Self.nuktaOverrides[sv] {
                    root = override
                    i += 2 // skip consonant + nukta
                } else {
                    root = Self.consonantRoots[sv] ?? ""
                    i += 1
                    if hasNukta { i += 1 } // skip nukta even without override
                }

                // Check what follows the consonant
                if i < scalars.count {
                    let nextSV = scalars[i].value
                    if nextSV == Self.virama {
                        // Halant: suppress inherent vowel
                        result.append(root)
                        i += 1
                    } else if let matraRoman = Self.matras[nextSV] {
                        // Matra: replace inherent vowel
                        result.append(root)
                        result.append(matraRoman)
                        i += 1
                        i = appendModifiers(scalars: scalars, index: i, result: &result)
                    } else {
                        // No matra, no halant: inherent "a"
                        result.append(root)
                        result.append("a")
                        i = appendModifiers(scalars: scalars, index: i, result: &result)
                    }
                } else {
                    // End of string: inherent "a"
                    result.append(root)
                    result.append("a")
                }
                continue
            }

            // Anusvara/visarga/chandrabindu standalone
            if sv == Self.anusvara {
                result.append("n")
                i += 1
                continue
            }
            if sv == Self.visarga {
                result.append("h")
                i += 1
                continue
            }
            if sv == Self.chandrabindu {
                result.append("n")
                i += 1
                continue
            }

            // Non-Devanagari scalar: pass through unchanged
            result.unicodeScalars.append(scalars[i])
            i += 1
            continue
        }

        return result
    }

    // MARK: - Helpers

    /// Check for and append anusvara, visarga, or chandrabindu at the current position.
    /// Returns the updated index.
    private func appendModifiers(scalars: [Unicode.Scalar], index: Int, result: inout String) -> Int {
        var i = index
        guard i < scalars.count else { return i }
        let sv = scalars[i].value
        if sv == Self.anusvara {
            result.append("n")
            i += 1
        } else if sv == Self.visarga {
            result.append("h")
            i += 1
        } else if sv == Self.chandrabindu {
            result.append("n")
            i += 1
        }
        return i
    }

    /// Returns `true` if the text contains any Devanagari characters.
    func containsDevanagari(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value >= 0x0900 && $0.value <= 0x097F }
    }
}
