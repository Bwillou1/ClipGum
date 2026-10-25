import Foundation

struct VerifiedModel: Equatable, Sendable {
    let manifest: ModelDownloadManifest
    let modelURL: URL
}

protocol ModelFileDownloading: Sendable {
    func download(_ url: URL, to destination: URL, expectedBytes: Int64) async throws
}

/// Explicit model acquisition is isolated from clipboard/inference services.
/// Files are streamed to a staging directory, verified, then moved as one unit.
actor ModelDownloadService {
    private let downloader: any ModelFileDownloading
    private let baseDirectory: URL

    init(
        downloader: any ModelFileDownloading = BoundedModelFileDownloader(),
        baseDirectory: URL? = nil
    ) {
        self.downloader = downloader
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
            self.baseDirectory = applicationSupport
                .appendingPathComponent("ClipGum", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
        }
    }

    func install(
        manifest unvalidatedManifest: ModelDownloadManifest,
        readiness: ModelReadiness
    ) async throws -> VerifiedModel {
        let manifest = try unvalidatedManifest.validated()
        guard
            readiness.isAppleSilicon,
            readiness.unifiedRAMBytes >= manifest.minimumUnifiedRAMBytes
        else {
            throw ModelDownloadError.insufficientMemory
        }

        let fileManager = FileManager.default
        let finalDirectory = baseDirectory.appendingPathComponent(manifest.identifier, isDirectory: true)
        let stagingDirectory = baseDirectory.appendingPathComponent(
            ".\(manifest.identifier)-\(UUID().uuidString).download",
            isDirectory: true
        )
        guard !fileManager.fileExists(atPath: finalDirectory.path) else {
            throw ModelDownloadError.destinationExists
        }

        do {
            try fileManager.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: true
            )
            for file in manifest.files {
                let destination = stagingDirectory.appendingPathComponent(file.name)
                try await downloader.download(file.url, to: destination, expectedBytes: file.expectedBytes)
                try ModelIntegrityVerifier.verify(fileAt: destination, expected: file)
            }
            try fileManager.moveItem(at: stagingDirectory, to: finalDirectory)
        } catch {
            try? fileManager.removeItem(at: stagingDirectory)
            if let modelError = error as? ModelDownloadError {
                throw modelError
            }
            throw ModelDownloadError.installationFailed
        }

        let modelURL = manifest.backend == .gguf
            ? finalDirectory.appendingPathComponent(manifest.files[0].name)
            : finalDirectory
        return VerifiedModel(manifest: manifest, modelURL: modelURL)
    }
}
