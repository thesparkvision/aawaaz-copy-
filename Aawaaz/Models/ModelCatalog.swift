import Foundation

struct ModelInfo: Identifiable, Equatable {
    let model: WhisperModel
    let fileName: String
    let downloadURL: URL
    let sizeDescription: String
    let sizeBytes: Int64
    let ramUsage: String
    let speed: String
    let hinglishQuality: String
    let recommendedFor: String

    var id: String { model.id }
}

enum ModelCatalog {
    private static let baseURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"

    static let models: [ModelInfo] = [
        ModelInfo(
            model: .small,
            fileName: "ggml-small-q5_0.bin",
            downloadURL: URL(string: baseURL + "ggml-small-q5_0.bin")!,
            sizeDescription: "~181 MB",
            sizeBytes: 181_000_000,
            ramUsage: "~1 GB",
            speed: "~3s",
            hinglishQuality: "Marginal",
            recommendedFor: "Low-RAM machines, quick notes"
        ),
        ModelInfo(
            model: .turbo,
            fileName: "ggml-large-v3-turbo-q5_0.bin",
            downloadURL: URL(string: baseURL + "ggml-large-v3-turbo-q5_0.bin")!,
            sizeDescription: "~547 MB",
            sizeBytes: 547_000_000,
            ramUsage: "~2.5 GB",
            speed: "~4s",
            hinglishQuality: "Good",
            recommendedFor: "Default — best trade-off"
        ),
        ModelInfo(
            model: .largeV3,
            fileName: "ggml-large-v3-q5_0.bin",
            downloadURL: URL(string: baseURL + "ggml-large-v3-q5_0.bin")!,
            sizeDescription: "~1.1 GB",
            sizeBytes: 1_100_000_000,
            ramUsage: "~4 GB",
            speed: "~8s",
            hinglishQuality: "Best",
            recommendedFor: "Quality mode, important dictation"
        ),
    ]

    static func info(for model: WhisperModel) -> ModelInfo {
        models.first { $0.model == model }!
    }
}
