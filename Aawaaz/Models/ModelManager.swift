import Foundation

@Observable
final class ModelManager {

    // MARK: - State

    var downloadedModels: Set<WhisperModel> = []
    var activeDownload: WhisperModel?
    var downloadProgress: Double = 0
    var downloadError: String?

    /// Called after downloadedModels changes so the app can reconcile selectedModel.
    var onModelsChanged: (() -> Void)?

    @ObservationIgnored
    private var downloadTask: URLSessionDownloadTask?
    @ObservationIgnored
    private var progressObservation: NSKeyValueObservation?

    // MARK: - Paths

    static let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Aawaaz/Models", isDirectory: true)
    }()

    // MARK: - Init

    init() {
        ensureModelsDirectory()
        scanDownloadedModels()
    }

    // MARK: - Public API

    func modelPath(for model: WhisperModel) -> String? {
        let info = ModelCatalog.info(for: model)
        let path = Self.modelsDirectory.appendingPathComponent(info.fileName).path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    func isDownloaded(_ model: WhisperModel) -> Bool {
        downloadedModels.contains(model)
    }

    func download(_ model: WhisperModel) {
        guard activeDownload == nil else { return }

        let info = ModelCatalog.info(for: model)
        activeDownload = model
        downloadProgress = 0
        downloadError = nil

        let task = URLSession.shared.downloadTask(with: info.downloadURL) { [weak self] tempURL, response, error in
            DispatchQueue.main.async {
                self?.handleDownloadCompletion(model: model, tempURL: tempURL, response: response, error: error)
            }
        }

        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.downloadProgress = progress.fractionCompleted
            }
        }

        downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        progressObservation?.invalidate()
        progressObservation = nil
        activeDownload = nil
        downloadProgress = 0
    }

    func deleteModel(_ model: WhisperModel) {
        let info = ModelCatalog.info(for: model)
        let path = Self.modelsDirectory.appendingPathComponent(info.fileName)
        try? FileManager.default.removeItem(at: path)
        downloadedModels.remove(model)
        onModelsChanged?()
    }

    // MARK: - Private

    private func ensureModelsDirectory() {
        try? FileManager.default.createDirectory(
            at: Self.modelsDirectory,
            withIntermediateDirectories: true
        )
    }

    private func scanDownloadedModels() {
        downloadedModels = []
        for info in ModelCatalog.models {
            let path = Self.modelsDirectory.appendingPathComponent(info.fileName)
            if FileManager.default.fileExists(atPath: path.path) {
                downloadedModels.insert(info.model)
            }
        }
    }

    private func handleDownloadCompletion(model: WhisperModel, tempURL: URL?, response: URLResponse?, error: Error?) {
        progressObservation?.invalidate()
        progressObservation = nil
        downloadTask = nil

        if let error = error as? NSError, error.code == NSURLErrorCancelled {
            activeDownload = nil
            return
        }

        guard let tempURL = tempURL, error == nil else {
            downloadError = error?.localizedDescription ?? "Download failed"
            activeDownload = nil
            return
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            downloadError = "Server returned status \(httpResponse.statusCode)"
            activeDownload = nil
            return
        }

        let info = ModelCatalog.info(for: model)
        let destination = Self.modelsDirectory.appendingPathComponent(info.fileName)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
            downloadedModels.insert(model)
            onModelsChanged?()
        } catch {
            downloadError = "Failed to save model: \(error.localizedDescription)"
        }

        activeDownload = nil
    }
}
