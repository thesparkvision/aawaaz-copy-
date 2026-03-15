import Foundation
import OnnxRuntimeBindings

/// Runs the xlm-roberta punctuation/truecasing model via ONNX Runtime.
///
/// Handles SentencePiece tokenization, sliding-window inference with overlap,
/// and text reconstruction with punctuation insertion + truecasing.
///
/// Optionally uses the CoreML execution provider for Apple Neural Engine (ANE)
/// acceleration. Falls back to CPU if CoreML session creation fails.
///
/// Thread-safe via actor isolation. Follows the same lazy-load pattern as
/// ``LocalLLMProcessor``.
actor PunctuationModelRunner {

    // MARK: - State

    enum ModelState: Sendable, Equatable {
        case unloaded
        case loading
        case loaded
        case error(String)
    }

    private(set) var modelState: ModelState = .unloaded

    private var env: ORTEnv?
    private var session: ORTSession?
    private var tokenizer: SentencePieceTokenizer?
    /// Whether the CoreML execution provider is actually active for the current session.
    /// May be false even when ANE was requested, if CoreML EP setup failed.
    private(set) var usingCoreML = false
    /// Tracks the ANE setting used for the current session so we can
    /// reload if the user toggles the setting.
    private var loadedWithANE: Bool?

    // MARK: - Config

    /// Maximum sequence length the model accepts (including BOS/EOS).
    private static let maxLength = 256
    /// Usable tokens per window (maxLength minus BOS and EOS).
    private static let maxTokens = maxLength - 2
    /// Number of overlap tokens between consecutive windows.
    private static let overlap = 16

    /// Label mapping from model's config.yaml.
    private static let preLabels = ["<NULL>", "¿"]
    private static let postLabels = [
        "<NULL>", "<ACRONYM>", ".", ",", "?", "？", "，", "。",
        "、", "・", "।", "؟", "،", ";", "።", "፣", "፧",
    ]
    private static let nullToken = "<NULL>"
    private static let acronymToken = "<ACRONYM>"

    /// SentencePiece space marker character.
    private static let spaceSymbol: Character = "▁"

    // MARK: - Model File Paths

    /// Expected model file names.
    private static let onnxFileName = "model_int8.onnx"
    private static let spFileName = "sp.model"

    /// Primary model directory inside the app's sandbox-accessible Application Support.
    ///
    /// Users should place `model_int8.onnx` and `sp.model` here:
    /// `~/Library/Application Support/Aawaaz/PunctuationModel/`
    static let appSupportModelDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Aawaaz", isDirectory: true)
            .appendingPathComponent("PunctuationModel", isDirectory: true)
    }()

    /// Resolve model file paths.
    ///
    /// Checks two locations in order:
    /// 1. `~/Library/Application Support/Aawaaz/PunctuationModel/` (sandbox-safe, preferred)
    /// 2. `~/.cache/huggingface/hub/...` (HF cache, works outside sandbox — for tests)
    ///
    /// Returns (onnxPath, spModelPath) or nil if files are not found in either location.
    static func resolveModelPaths() -> (onnx: String, sp: String)? {
        // 1. Application Support (sandbox-accessible)
        let appOnnx = appSupportModelDir.appendingPathComponent(onnxFileName).path
        let appSP = appSupportModelDir.appendingPathComponent(spFileName).path
        if FileManager.default.fileExists(atPath: appOnnx),
           FileManager.default.fileExists(atPath: appSP) {
            return (appOnnx, appSP)
        }

        // 2. HuggingFace cache (fallback for non-sandboxed contexts like tests)
        if let hfPaths = resolveHFCachePaths() {
            return hfPaths
        }

        return nil
    }

    /// Resolve from HuggingFace cache. Only works outside the app sandbox.
    private static func resolveHFCachePaths() -> (onnx: String, sp: String)? {
        let suffix = ".cache/huggingface/hub/models--1-800-BAD-CODE--xlm-roberta_punctuation_fullstop_truecase/snapshots"
        let home: String
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            home = String(cString: dir)
        } else {
            home = NSHomeDirectory()
        }

        let baseDir = "\(home)/\(suffix)"
        guard let snapshots = try? FileManager.default.contentsOfDirectory(atPath: baseDir),
              let snapshot = snapshots.first(where: { !$0.hasPrefix(".") }) else {
            return nil
        }
        let dir = "\(baseDir)/\(snapshot)"
        let onnx = "\(dir)/\(onnxFileName)"
        let sp = "\(dir)/\(spFileName)"
        guard FileManager.default.fileExists(atPath: onnx),
              FileManager.default.fileExists(atPath: sp) else { return nil }
        return (onnx, sp)
    }

    /// Whether the punctuation model files are available on disk.
    static var isAvailable: Bool { resolveModelPaths() != nil }

    // MARK: - Load / Unload

    /// Load the ONNX model and tokenizer.
    ///
    /// - Parameter useANE: Whether to enable the CoreML execution provider for ANE acceleration.
    /// - Throws: ``PunctuationModelError`` if files are missing or loading fails.
    func loadModel(useANE: Bool = true) throws {
        // If already loaded with the same ANE setting, skip
        if modelState == .loaded && loadedWithANE == useANE { return }
        // If loaded but ANE setting changed, unload first
        if modelState == .loaded { unload() }
        modelState = .loading

        guard let paths = Self.resolveModelPaths() else {
            modelState = .error("Model files not found")
            throw PunctuationModelError.modelNotFound
        }

        do {
            let tok = try SentencePieceTokenizer(modelPath: paths.sp)
            let ortEnv = try ORTEnv(loggingLevel: .warning)
            let options = try ORTSessionOptions()

            // Try CoreML EP for ANE acceleration
            var coreMLActive = false
            if useANE {
                coreMLActive = Self.tryEnableCoreML(options: options)
            }

            let ortSession = try ORTSession(env: ortEnv, modelPath: paths.onnx, sessionOptions: options)

            self.env = ortEnv
            self.session = ortSession
            self.tokenizer = tok
            self.usingCoreML = coreMLActive
            self.loadedWithANE = useANE
            self.modelState = .loaded

            print("[PunctModel] Loaded (CoreML/ANE: \(coreMLActive ? "ON" : "OFF"))")
        } catch {
            modelState = .error(error.localizedDescription)
            throw error
        }
    }

    /// Unload the model and free memory.
    func unload() {
        session = nil
        env = nil
        tokenizer = nil
        usingCoreML = false
        loadedWithANE = nil
        modelState = .unloaded
    }

    /// Try to enable the CoreML execution provider.
    /// Returns true if successful, false if CoreML is unavailable.
    private static func tryEnableCoreML(options: ORTSessionOptions) -> Bool {
        do {
            let coreMLOptions = ORTCoreMLExecutionProviderOptions()
            // Use CPU + ANE (default). Don't set useCPUOnly or useCPUAndGPU.
            coreMLOptions.onlyAllowStaticInputShapes = false
            coreMLOptions.createMLProgram = true
            try options.appendCoreMLExecutionProvider(with: coreMLOptions)
            return true
        } catch {
            print("[PunctModel] CoreML EP unavailable, using CPU: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Input Analysis

    /// Sentence-ending punctuation characters.
    private static let sentencePunctuation = CharacterSet(charactersIn: ".?!;:。？！；：")
    /// Punctuation to strip before feeding the model (sentence-level only).
    /// Keeps apostrophes inside words (don't, it's).
    private static let stripPattern = try! NSRegularExpression(
        pattern: #"[\.,:;\?!？！。，；：।؟،።፣፧]"#)
    /// Collapse repeated sentence-ending punctuation.
    private static let collapsePattern = try! NSRegularExpression(pattern: #"([\.?!])\1+"#)
    /// Spaces before punctuation.
    private static let spacePunctPattern = try! NSRegularExpression(pattern: #"\s+([\.,:;?!])"#)

    /// Whether the given text already has meaningful sentence punctuation from Whisper.
    ///
    /// Heuristic: text is "punctuated" if it contains `?` or `!`, has 2+ sentence-ending marks,
    /// or has an internal sentence-ending mark (a period/mark not at the very end).
    /// A single trailing period on an otherwise unpunctuated utterance is NOT considered
    /// well-punctuated since it may be a run-on that the model can help with.
    static func isAlreadyPunctuated(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Question marks or exclamation marks → Whisper was confident about sentence type
        if trimmed.contains("?") || trimmed.contains("!") { return true }

        // Count sentence-ending marks
        let endMarks = trimmed.unicodeScalars.filter { sentencePunctuation.contains($0) }.count
        if endMarks >= 2 { return true }

        // Check for internal sentence-ending punctuation (not at the very end).
        // E.g. "I don't know. can you tell me" has an internal period.
        if endMarks == 1 {
            let lastChar = trimmed.unicodeScalars.last!
            if !sentencePunctuation.contains(lastChar) {
                return true
            }
        }

        return false
    }

    /// Normalize text for the punct model's training distribution: lowercase + strip sentence punctuation.
    /// Keeps apostrophes inside words (don't, it's) and punctuation between digits (3.14, 10:30, 1,000).
    static func normalizeForModel(_ text: String) -> String {
        let lowered = text.lowercased()
        let nsLowered = lowered as NSString
        let range = NSRange(location: 0, length: nsLowered.length)

        // Use a block-based replacement to skip punctuation between digits
        var result = ""
        var lastEnd = 0
        stripPattern.enumerateMatches(in: lowered, range: range) { match, _, _ in
            guard let match else { return }
            let matchRange = match.range

            // Append text before this match
            let beforeRange = NSRange(location: lastEnd, length: matchRange.location - lastEnd)
            result += nsLowered.substring(with: beforeRange)

            // Check if match is between digits → preserve it
            let charBefore = matchRange.location > 0
                ? nsLowered.character(at: matchRange.location - 1)
                : 0
            let afterIdx = matchRange.location + matchRange.length
            let charAfter = afterIdx < nsLowered.length
                ? nsLowered.character(at: afterIdx)
                : 0
            let digitBefore = CharacterSet.decimalDigits.contains(UnicodeScalar(charBefore) ?? UnicodeScalar(0))
            let digitAfter = CharacterSet.decimalDigits.contains(UnicodeScalar(charAfter) ?? UnicodeScalar(0))

            if digitBefore && digitAfter {
                // Keep punctuation between digits (3.14, 10:30, 1,000)
                result += nsLowered.substring(with: matchRange)
            }
            // Otherwise strip it (the default)

            lastEnd = matchRange.location + matchRange.length
        }
        // Append remaining text
        if lastEnd < nsLowered.length {
            result += nsLowered.substring(from: lastEnd)
        }
        return result
    }

    /// Collapse doubled punctuation marks that can occur if the model or Whisper both add them.
    static func sanitizePunctuation(_ text: String) -> String {
        var result = text
        // Collapse repeated punctuation: .. → .  ?? → ?  !! → !
        result = collapsePattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "$1")
        // Remove spaces before punctuation: "word . more" → "word. more"
        result = spacePunctPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "$1")
        return result
    }

    // MARK: - Inference

    /// Run punctuation and truecasing inference on the given text.
    ///
    /// The model was trained on unpunctuated, lowercased text. When the input
    /// already contains meaningful punctuation from Whisper, the model is
    /// skipped to avoid doubled/corrupted punctuation. When the model does run,
    /// input is normalized first and a post-sanitizer catches any remaining
    /// doubled marks.
    ///
    /// - Parameter text: Input text (output of the deterministic pipeline).
    /// - Returns: Text with punctuation marks inserted and proper capitalization applied.
    /// - Throws: If the model is not loaded or inference fails.
    func predict(_ text: String) throws -> String {
        guard let session, let tokenizer else {
            throw PunctuationModelError.modelNotLoaded
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        // Skip the model if Whisper already provided meaningful punctuation.
        // The model doubles existing punctuation, causing "?" → "??" → LLM → ".".
        if Self.isAlreadyPunctuated(trimmed) {
            print("[PunctModel] Skipping — input already punctuated")
            return text
        }

        // Normalize to the model's training distribution: lowercase + strip sentence punct
        let normalized = Self.normalizeForModel(trimmed)
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }

        // Tokenize the normalized input
        let allIDs = tokenizer.encodeAsIDs(normalized)
        guard !allIDs.isEmpty else { return text }

        // Create sliding windows
        let windows = createWindows(tokenIDs: allIDs)

        // Run inference on each window
        var allPredictions: [WindowPredictions] = []
        for window in windows {
            let preds = try runInference(session: session, inputIDs: window, tokenizer: tokenizer)
            allPredictions.append(preds)
        }

        // Merge predictions from overlapping windows
        let merged = mergePredictions(allPredictions, totalTokens: allIDs.count)

        // Validate merged predictions align with input tokens
        guard merged.prePreds.count == allIDs.count else {
            throw PunctuationModelError.invalidOutput(
                "Merged predictions (\(merged.prePreds.count)) != token count (\(allIDs.count))")
        }

        // Reconstruct text from tokens and predictions
        let result = reconstruct(
            tokenIDs: allIDs,
            predictions: merged,
            tokenizer: tokenizer
        )

        // Safety: collapse any doubled punctuation that slipped through
        return Self.sanitizePunctuation(result)
    }

    // MARK: - Sliding Window

    /// Per-window inference results (BOS/EOS already stripped).
    private struct WindowPredictions {
        let prePreds: [Int]
        let postPreds: [Int]
        let capPreds: [[Bool]]
        let sbdPreds: [Bool]
        let tokenCount: Int
    }

    /// Merged predictions for all tokens.
    private struct MergedPredictions {
        let prePreds: [Int]
        let postPreds: [Int]
        let capPreds: [[Bool]]
        let sbdPreds: [Bool]
    }

    /// Split token IDs into overlapping windows.
    ///
    /// Each window contains up to `maxTokens` tokens. Consecutive windows
    /// overlap by `overlap` tokens. BOS/EOS are not included here — they're
    /// added during inference.
    private func createWindows(tokenIDs: [Int]) -> [[Int]] {
        let maxTok = Self.maxTokens
        let overlap = Self.overlap

        var windows: [[Int]] = []
        var start = 0
        var inputIdx = 0

        while start < tokenIDs.count {
            let adjustedStart = start - (inputIdx == 0 ? 0 : overlap)
            let stop = min(adjustedStart + maxTok, tokenIDs.count)
            windows.append(Array(tokenIDs[adjustedStart..<stop]))
            start = stop
            inputIdx += 1
        }

        return windows
    }

    /// Run ONNX inference on a single window of token IDs.
    ///
    /// Wraps input with BOS/EOS, pads to maxLength, runs the session,
    /// and strips BOS/EOS from the output predictions.
    private func runInference(
        session: ORTSession,
        inputIDs: [Int],
        tokenizer: SentencePieceTokenizer
    ) throws -> WindowPredictions {
        // Build input: [BOS] + tokens + [EOS] + padding
        var paddedIDs = [Int64(tokenizer.bosID)] + inputIDs.map(Int64.init) + [Int64(tokenizer.eosID)]
        let actualLength = paddedIDs.count
        while paddedIDs.count < Self.maxLength {
            paddedIDs.append(Int64(tokenizer.padID))
        }

        // Create input tensor [1, maxLength]
        let inputData = paddedIDs.withUnsafeBufferPointer { bufferPtr in
            NSMutableData(bytes: bufferPtr.baseAddress!, length: bufferPtr.count * MemoryLayout<Int64>.size)
        }
        let inputTensor = try ORTValue(
            tensorData: inputData,
            elementType: .int64,
            shape: [1, NSNumber(value: Self.maxLength)]
        )

        // Run inference
        let outputs = try session.run(
            withInputs: ["input_ids": inputTensor],
            outputNames: Set(["pre_preds", "post_preds", "cap_preds", "seg_preds"]),
            runOptions: nil
        )

        // Extract outputs (strip BOS/EOS: indices 1..<actualLength-1)
        let tokenCount = actualLength - 2 // without BOS/EOS

        let prePreds = try extractInt64Output(outputs["pre_preds"], seqLen: Self.maxLength, start: 1, count: tokenCount)
        let postPreds = try extractInt64Output(outputs["post_preds"], seqLen: Self.maxLength, start: 1, count: tokenCount)
        let capPreds = try extractInt32AsCapBoolOutput(outputs["cap_preds"], seqLen: Self.maxLength, start: 1, count: tokenCount)
        let sbdPreds = try extractInt32AsBoolOutput(outputs["seg_preds"], seqLen: Self.maxLength, start: 1, count: tokenCount)

        return WindowPredictions(
            prePreds: prePreds,
            postPreds: postPreds,
            capPreds: capPreds,
            sbdPreds: sbdPreds,
            tokenCount: tokenCount
        )
    }

    // MARK: - Output Extraction Helpers

    /// Extract int64 predictions from an ORTValue [1, seqLen].
    private func extractInt64Output(_ value: ORTValue?, seqLen: Int, start: Int, count: Int) throws -> [Int] {
        guard let value else { throw PunctuationModelError.inferenceOutputMissing }
        let data = try value.tensorData() as Data
        return data.withUnsafeBytes { ptr in
            let buffer = ptr.bindMemory(to: Int64.self)
            return (start..<(start + count)).map { Int(buffer[$0]) }
        }
    }

    /// Extract int32 predictions (used for seg_preds after bool→int32 cast) as booleans.
    private func extractInt32AsBoolOutput(_ value: ORTValue?, seqLen: Int, start: Int, count: Int) throws -> [Bool] {
        guard let value else { throw PunctuationModelError.inferenceOutputMissing }
        let data = try value.tensorData() as Data
        return data.withUnsafeBytes { ptr in
            let buffer = ptr.bindMemory(to: Int32.self)
            return (start..<(start + count)).map { buffer[$0] != 0 }
        }
    }

    /// Extract int32 capitalization predictions from an ORTValue [1, seqLen, 16] as booleans.
    private func extractInt32AsCapBoolOutput(_ value: ORTValue?, seqLen: Int, start: Int, count: Int) throws -> [[Bool]] {
        guard let value else { throw PunctuationModelError.inferenceOutputMissing }
        let data = try value.tensorData() as Data
        let capDim = 16
        return data.withUnsafeBytes { ptr in
            let buffer = ptr.bindMemory(to: Int32.self)
            return (start..<(start + count)).map { tokenIdx in
                (0..<capDim).map { charIdx in
                    buffer[tokenIdx * capDim + charIdx] != 0
                }
            }
        }
    }

    // MARK: - Prediction Merging

    /// Merge predictions from overlapping windows.
    ///
    /// For each overlapping region, drops `overlap/2` tokens from the end of
    /// the left window and `overlap/2` from the start of the right window.
    /// This selects predictions from the center of each window where context
    /// is strongest.
    private func mergePredictions(_ windows: [WindowPredictions], totalTokens: Int) -> MergedPredictions {
        let halfOverlap = Self.overlap / 2
        var prePreds: [Int] = []
        var postPreds: [Int] = []
        var capPreds: [[Bool]] = []
        var sbdPreds: [Bool] = []

        for (i, w) in windows.enumerated() {
            let start = (i > 0) ? halfOverlap : 0
            let stop = (i < windows.count - 1) ? (w.tokenCount - halfOverlap) : w.tokenCount

            prePreds.append(contentsOf: w.prePreds[start..<stop])
            postPreds.append(contentsOf: w.postPreds[start..<stop])
            capPreds.append(contentsOf: w.capPreds[start..<stop])
            sbdPreds.append(contentsOf: w.sbdPreds[start..<stop])
        }

        return MergedPredictions(
            prePreds: prePreds,
            postPreds: postPreds,
            capPreds: capPreds,
            sbdPreds: sbdPreds
        )
    }

    // MARK: - Text Reconstruction

    /// Reconstruct text from token IDs and predictions.
    ///
    /// Replicates the Python PCSResultCollector logic exactly:
    /// - Space: if piece starts with ▁ and output has content, append space
    /// - Skip ▁ character, but keep original piece index for cap_preds
    /// - Pre-punctuation: insert before first real character
    /// - Cap predictions: indexed by position in ORIGINAL piece string
    /// - ACRONYM: insert "." after every character
    /// - Post-punctuation: insert after last char of original piece
    /// - SBD: finalize sentence after last char of original piece
    private func reconstruct(
        tokenIDs: [Int],
        predictions: MergedPredictions,
        tokenizer: SentencePieceTokenizer
    ) -> String {
        var sentences: [String] = []
        var currentChars: [Character] = []

        for (tokenIdx, tokenID) in tokenIDs.enumerated() {
            let piece = tokenizer.idToPiece(tokenID)
            let pieceChars = Array(piece)

            // Space handling: if piece starts with ▁ and we have prior output, add space
            if piece.first == Self.spaceSymbol, !currentChars.isEmpty {
                currentChars.append(" ")
            }

            // Determine char_start: skip ▁ prefix
            let charStart = piece.first == Self.spaceSymbol ? 1 : 0

            // Iterate real characters, using original piece index for predictions
            for pieceCharIdx in charStart..<pieceChars.count {
                let ch = pieceChars[pieceCharIdx]

                // Pre-punctuation: insert before first real character
                if pieceCharIdx == charStart {
                    let preLabel = predictions.prePreds[tokenIdx]
                    if preLabel < Self.preLabels.count {
                        let label = Self.preLabels[preLabel]
                        if label != Self.nullToken {
                            currentChars.append(contentsOf: label)
                        }
                    }
                }

                // Apply capitalization using ORIGINAL piece index
                var outChar = ch
                if tokenIdx < predictions.capPreds.count,
                   pieceCharIdx < predictions.capPreds[tokenIdx].count,
                   predictions.capPreds[tokenIdx][pieceCharIdx] {
                    outChar = Character(String(ch).uppercased())
                }
                currentChars.append(outChar)

                // Post-punctuation
                let postLabel = predictions.postPreds[tokenIdx]
                if postLabel < Self.postLabels.count {
                    let label = Self.postLabels[postLabel]
                    if label == Self.acronymToken {
                        // ACRONYM: insert period after every character
                        currentChars.append(".")
                    } else if pieceCharIdx == pieceChars.count - 1, label != Self.nullToken {
                        // Regular post-punctuation: only on last char of original piece
                        currentChars.append(contentsOf: label)
                    }
                }

                // Sentence boundary detection (on last char of original piece)
                if pieceCharIdx == pieceChars.count - 1, predictions.sbdPreds[tokenIdx] {
                    sentences.append(String(currentChars))
                    currentChars = []
                }
            }
        }

        // Flush remaining characters
        if !currentChars.isEmpty {
            sentences.append(String(currentChars))
        }

        return sentences.joined(separator: " ")
    }
}

// MARK: - Errors

enum PunctuationModelError: Error, LocalizedError {
    case modelNotFound
    case modelNotLoaded
    case inferenceOutputMissing
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Punctuation model files not found. Download the model first."
        case .modelNotLoaded:
            return "Punctuation model not loaded. Call loadModel() first."
        case .inferenceOutputMissing:
            return "ONNX inference did not produce expected output tensors."
        case .invalidOutput(let detail):
            return "Invalid model output: \(detail)"
        }
    }
}
