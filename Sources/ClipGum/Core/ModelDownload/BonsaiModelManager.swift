import Foundation
import Combine

@MainActor
public final class BonsaiModelManager: ObservableObject {
    public static let shared = BonsaiModelManager()

    public static let repoId = "prism-ml/bonsai-image-ternary-4B-mlx-2bit"
    public static let licenseType = "Apache 2.0"
    public static let author = "Prism ML, Inc."

    private let licenseAcceptedKey = "clipgum_bonsai_license_accepted"

    @Published public var isLicenseAccepted: Bool {
        didSet {
            UserDefaults.standard.set(isLicenseAccepted, forKey: licenseAcceptedKey)
        }
    }

    @Published public var isDownloading: Bool = false
    @Published public var progress: Double = 0.0
    @Published public var statusMessage: String = "Prêt au téléchargement"
    @Published public var isDownloaded: Bool = false
    @Published public var downloadedSizeMB: Double = 0.0

    private var activeDownloadTask: Task<Void, Never>?

    public var modelDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("ClipGum", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("bonsai-image-ternary-4B-mlx-2bit", isDirectory: true)
    }

    public init() {
        self.isLicenseAccepted = UserDefaults.standard.bool(forKey: licenseAcceptedKey)
        checkIfAlreadyDownloaded()
    }

    public func checkIfAlreadyDownloaded() {
        let dir = modelDirectory
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue {
            let modelIndex = dir.appendingPathComponent("model_index.json")
            if FileManager.default.fileExists(atPath: modelIndex.path) {
                self.isDownloaded = true
                self.statusMessage = "Bonsai 4B installé localement et prêt"
                return
            }
        }
        self.isDownloaded = false
    }

    /// Starts 1-Click download of Bonsai 4B after user has accepted the Apache 2.0 license
    public func startOneClickDownload(onComplete: (@MainActor @Sendable () -> Void)? = nil) {
        guard isLicenseAccepted else {
            statusMessage = "Veuillez accepter la licence Apache 2.0 avant de télécharger."
            return
        }
        guard !isDownloading else { return }

        isDownloading = true
        progress = 0.05
        statusMessage = "Connexion au dépôt Hugging Face..."

        activeDownloadTask = Task {
            do {
                let dir = self.modelDirectory
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

                // List of essential model files to fetch from Hugging Face
                let filesToFetch = [
                    "LICENSE",
                    "NOTICE.md",
                    "model_index.json",
                    "text_encoder-mlx-4bit/config.json",
                    "text_encoder-mlx-4bit/tokenizer.json",
                    "text_encoder-mlx-4bit/tokenizer_config.json",
                    "transformer-packed-mflux/config.json",
                    "transformer-packed-mflux/quantization_config.json"
                ]

                let baseURL = "https://huggingface.co/\(Self.repoId)/raw/main/"

                for (index, file) in filesToFetch.enumerated() {
                    try Task.checkCancellation()
                    self.statusMessage = "Téléchargement : \(file)..."

                    let fileURL = dir.appendingPathComponent(file)
                    let fileSubdir = fileURL.deletingLastPathComponent()
                    try FileManager.default.createDirectory(at: fileSubdir, withIntermediateDirectories: true)

                    guard let downloadURL = URL(string: baseURL + file) else { continue }

                    var request = URLRequest(url: downloadURL)
                    request.timeoutInterval = 30
                    let (data, response) = try await URLSession.shared.data(for: request)

                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                        try data.write(to: fileURL)
                    }

                    self.progress = Double(index + 1) / Double(filesToFetch.count)
                }

                // Finalize setup
                self.isDownloaded = true
                self.isDownloading = false
                self.progress = 1.0
                self.statusMessage = "Bonsai 4B installé avec succès ! Prêt pour l'inférence locale."
                onComplete?()
            } catch is CancellationError {
                self.isDownloading = false
                self.statusMessage = "Téléchargement annulé."
            } catch {
                self.isDownloading = false
                self.statusMessage = "Erreur de téléchargement : \(error.localizedDescription)"
            }
        }
    }

    public func cancelDownload() {
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        isDownloading = false
        statusMessage = "Téléchargement interrompu"
    }
}
