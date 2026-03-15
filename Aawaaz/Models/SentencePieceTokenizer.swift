import Foundation

/// Minimal SentencePiece unigram tokenizer for the xlm-roberta punctuation model.
///
/// Parses a SentencePiece `.model` protobuf file, extracts the vocabulary, and
/// implements the Viterbi-based unigram encoding algorithm. Only supports the
/// UNIGRAM model type — BPE, WORD, and CHAR are not implemented.
///
/// Designed to match the behavior of the Python `sentencepiece` library for the
/// `1-800-BAD-CODE/xlm-roberta_punctuation_fullstop_truecase` model.
struct SentencePieceTokenizer {

    // MARK: - Vocabulary

    /// A single vocabulary entry.
    private struct Piece {
        let text: String
        let score: Float
        let type: PieceType
    }

    /// SentencePiece piece types (from sentencepiece_model.proto).
    private enum PieceType: Int {
        case normal = 1
        case unknown = 2
        case control = 3
        case userDefined = 4
        case unused = 5
        case byte = 6
    }

    private let pieces: [Piece]
    /// piece text → piece index for fast lookup.
    private let pieceToID: [String: Int]

    // MARK: - Special Token IDs

    let bosID: Int // <s>
    let eosID: Int // </s>
    let padID: Int // <pad>
    let unkID: Int

    // MARK: - Config

    /// The sentinel character that replaces whitespace in SentencePiece.
    private static let spaceSymbol: Character = "▁" // U+2581

    /// Prepend a space before the input text (SentencePiece `add_dummy_prefix`).
    private let addDummyPrefix: Bool
    /// Collapse multiple whitespace characters into one.
    private let removeExtraWhitespaces: Bool

    // MARK: - Trie for Viterbi

    /// Trie node for efficient prefix matching during Viterbi encoding.
    private final class TrieNode {
        var children: [Character: TrieNode] = [:]
        /// Piece index if this node terminates a piece, nil otherwise.
        var pieceIndex: Int?
    }

    private let trieRoot: TrieNode

    // MARK: - Init

    /// Load a SentencePiece model from a `.model` file.
    ///
    /// - Parameter path: Absolute path to the `.model` file (protobuf format).
    /// - Throws: If the file cannot be read or parsed.
    init(modelPath path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let parsed = try Self.parseModelProto(data)

        self.pieces = parsed.pieces
        self.addDummyPrefix = parsed.addDummyPrefix
        self.removeExtraWhitespaces = parsed.removeExtraWhitespaces

        // Build piece → ID lookup
        var lookup: [String: Int] = [:]
        lookup.reserveCapacity(pieces.count)
        for (i, p) in pieces.enumerated() {
            lookup[p.text] = i
        }
        self.pieceToID = lookup

        // Find special tokens
        self.bosID = lookup["<s>"] ?? 0
        self.eosID = lookup["</s>"] ?? 2
        self.padID = lookup["<pad>"] ?? 1
        self.unkID = lookup["<unk>"] ?? 3

        // Build trie from normal pieces only
        let root = TrieNode()
        for (i, p) in pieces.enumerated() {
            guard p.type == .normal || p.type == .userDefined else { continue }
            var node = root
            for ch in p.text {
                if node.children[ch] == nil {
                    node.children[ch] = TrieNode()
                }
                node = node.children[ch]!
            }
            node.pieceIndex = i
        }
        self.trieRoot = root
    }

    // MARK: - Public API

    /// Number of vocabulary entries.
    var vocabSize: Int { pieces.count }

    /// Encode text into token IDs using the unigram Viterbi algorithm.
    ///
    /// Applies SentencePiece normalization (NFKC, whitespace handling, dummy
    /// prefix) before encoding.
    ///
    /// - Parameter text: Input text to tokenize.
    /// - Returns: Array of token IDs (without BOS/EOS).
    func encodeAsIDs(_ text: String) -> [Int] {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return [] }
        return viterbiEncode(normalized)
    }

    /// Get the piece string for a token ID.
    ///
    /// - Parameter id: Token ID.
    /// - Returns: The piece string, or `"<unk>"` if the ID is out of range.
    func idToPiece(_ id: Int) -> String {
        guard id >= 0, id < pieces.count else { return "<unk>" }
        return pieces[id].text
    }

    // MARK: - Normalization

    /// Apply SentencePiece normalization to input text.
    ///
    /// Steps:
    /// 1. NFKC Unicode normalization
    /// 2. Optionally remove extra whitespace
    /// 3. Optionally add dummy prefix (prepend space)
    /// 4. Replace spaces with ▁
    private func normalize(_ text: String) -> String {
        // NFKC normalization (matches nmt_nfkc)
        var result = text.precomposedStringWithCompatibilityMapping

        // Remove extra whitespace: collapse runs of whitespace to single space, trim
        if removeExtraWhitespaces {
            let parts = result.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            result = parts.joined(separator: " ")
        }

        guard !result.isEmpty else { return "" }

        // Add dummy prefix (prepend space before replacing spaces with ▁)
        if addDummyPrefix {
            result = " " + result
        }

        // Escape whitespace: replace spaces with ▁
        result = result.map { $0 == " " ? Self.spaceSymbol : $0 }
            .map(String.init).joined()

        return result
    }

    // MARK: - Viterbi Encoding

    /// Unigram Viterbi algorithm for optimal tokenization.
    ///
    /// Finds the segmentation that maximizes the total log probability
    /// (sum of piece scores). Uses a trie for efficient prefix matching.
    private func viterbiEncode(_ normalized: String) -> [Int] {
        let chars = Array(normalized)
        let n = chars.count

        // best[i] = best score to tokenize chars[0..<i]
        // backtrack[i] = (start_position, piece_id) for the best piece ending at i
        var best = [Float](repeating: -.infinity, count: n + 1)
        var backtrack = [(start: Int, pieceID: Int)](repeating: (0, unkID), count: n + 1)
        best[0] = 0

        for i in 0..<n {
            guard best[i] > -.infinity else { continue }

            // Walk the trie from position i
            var node = trieRoot
            for j in i..<n {
                guard let next = node.children[chars[j]] else { break }
                node = next
                if let pieceIdx = node.pieceIndex {
                    let score = best[i] + pieces[pieceIdx].score
                    if score > best[j + 1] {
                        best[j + 1] = score
                        backtrack[j + 1] = (i, pieceIdx)
                    }
                }
            }

            // Handle unknown character: if no piece starts here and we can't advance,
            // treat the single character as <unk>
            if best[i + 1] == -.infinity || best[i + 1] < best[i] - 100 {
                // Check if we genuinely have no match for this character
                if trieRoot.children[chars[i]] == nil {
                    let score = best[i] - 100 // Heavy penalty for unknown
                    if score > best[i + 1] {
                        best[i + 1] = score
                        backtrack[i + 1] = (i, unkID)
                    }
                }
            }
        }

        // Backtrack to recover the optimal segmentation
        var ids: [Int] = []
        var pos = n
        while pos > 0 {
            let (start, pieceID) = backtrack[pos]
            ids.append(pieceID)
            pos = start
        }
        ids.reverse()
        return ids
    }

    // MARK: - Protobuf Parsing

    /// Parsed model data.
    private struct ParsedModel {
        let pieces: [Piece]
        let addDummyPrefix: Bool
        let removeExtraWhitespaces: Bool
    }

    /// Minimal protobuf parser for SentencePiece ModelProto.
    ///
    /// Only extracts fields needed for tokenization:
    /// - Field 1 (pieces): repeated SentencePiece messages
    /// - Field 3 (normalizer_spec): NormalizerSpec message
    ///
    /// Wire format:
    /// - Varint: field_number << 3 | wire_type
    /// - Wire type 0: varint, 2: length-delimited, 5: 32-bit fixed
    private static func parseModelProto(_ data: Data) throws -> ParsedModel {
        var pieces: [Piece] = []
        var addDummyPrefix = true
        var removeExtraWhitespaces = true

        var offset = 0
        while offset < data.count {
            let (tag, newOffset) = readVarint(data, offset: offset)
            offset = newOffset

            let fieldNumber = tag >> 3
            let wireType = tag & 0x07

            switch wireType {
            case 0: // Varint
                let (_, nextOffset) = readVarint(data, offset: offset)
                offset = nextOffset

            case 1: // 64-bit fixed
                offset += 8

            case 2: // Length-delimited
                let (length, lenOffset) = readVarint(data, offset: offset)
                offset = lenOffset
                let endOffset = offset + Int(length)

                if fieldNumber == 1 {
                    // SentencePiece message
                    let piece = parseSentencePiece(data, start: offset, end: endOffset)
                    pieces.append(piece)
                } else if fieldNumber == 3 {
                    // NormalizerSpec message
                    let (dummy, removeExtra) = parseNormalizerSpec(data, start: offset, end: endOffset)
                    addDummyPrefix = dummy
                    removeExtraWhitespaces = removeExtra
                }
                offset = endOffset

            case 5: // 32-bit fixed
                offset += 4

            default:
                throw TokenizerError.invalidProtobuf("Unknown wire type \(wireType)")
            }
        }

        return ParsedModel(pieces: pieces, addDummyPrefix: addDummyPrefix,
                           removeExtraWhitespaces: removeExtraWhitespaces)
    }

    /// Parse a single SentencePiece message (fields: 1=piece, 2=score, 4=type).
    private static func parseSentencePiece(_ data: Data, start: Int, end: Int) -> Piece {
        var pieceText = ""
        var score: Float = 0
        var type: PieceType = .normal

        var offset = start
        while offset < end {
            let (tag, newOffset) = readVarint(data, offset: offset)
            offset = newOffset

            let fieldNumber = tag >> 3
            let wireType = tag & 0x07

            switch wireType {
            case 0: // Varint
                let (value, nextOffset) = readVarint(data, offset: offset)
                offset = nextOffset
                if fieldNumber == 4 { // type
                    type = PieceType(rawValue: Int(value)) ?? .normal
                }

            case 2: // Length-delimited (string)
                let (length, lenOffset) = readVarint(data, offset: offset)
                offset = lenOffset
                if fieldNumber == 1 { // piece string
                    pieceText = String(data: data[offset..<(offset + Int(length))], encoding: .utf8) ?? ""
                }
                offset += Int(length)

            case 5: // 32-bit fixed (float)
                if fieldNumber == 2 { // score
                    var raw: UInt32 = 0
                    raw |= UInt32(data[offset])
                    raw |= UInt32(data[offset + 1]) << 8
                    raw |= UInt32(data[offset + 2]) << 16
                    raw |= UInt32(data[offset + 3]) << 24
                    score = Float(bitPattern: raw)
                }
                offset += 4

            case 1: // 64-bit fixed
                offset += 8

            default:
                break
            }
        }

        return Piece(text: pieceText, score: score, type: type)
    }

    /// Parse NormalizerSpec (fields: 3=add_dummy_prefix, 5=remove_extra_whitespaces).
    private static func parseNormalizerSpec(_ data: Data, start: Int, end: Int) -> (addDummyPrefix: Bool, removeExtraWhitespaces: Bool) {
        var addDummyPrefix = true
        var removeExtraWhitespaces = true

        var offset = start
        while offset < end {
            let (tag, newOffset) = readVarint(data, offset: offset)
            offset = newOffset

            let fieldNumber = tag >> 3
            let wireType = tag & 0x07

            switch wireType {
            case 0:
                let (value, nextOffset) = readVarint(data, offset: offset)
                offset = nextOffset
                if fieldNumber == 3 { addDummyPrefix = value != 0 }
                if fieldNumber == 5 { removeExtraWhitespaces = value != 0 }

            case 2:
                let (length, lenOffset) = readVarint(data, offset: offset)
                offset = lenOffset + Int(length)

            case 5:
                offset += 4

            case 1:
                offset += 8

            default:
                break
            }
        }

        return (addDummyPrefix, removeExtraWhitespaces)
    }

    /// Read a varint from the data at the given offset.
    /// Returns (value, newOffset).
    private static func readVarint(_ data: Data, offset: Int) -> (UInt64, Int) {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var pos = offset
        while pos < data.count {
            let byte = data[pos]
            result |= UInt64(byte & 0x7F) << shift
            pos += 1
            if byte & 0x80 == 0 { break }
            shift += 7
        }
        return (result, pos)
    }
}

// MARK: - Errors

enum TokenizerError: Error, LocalizedError {
    case modelNotFound
    case invalidProtobuf(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "SentencePiece model file not found"
        case .invalidProtobuf(let detail):
            return "Failed to parse SentencePiece model: \(detail)"
        }
    }
}
