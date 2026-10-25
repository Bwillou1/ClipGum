import AppKit
import Foundation

@MainActor
final class ModelDownloadController: ObservableObject {
    @Published private(set) var manifest: ModelDownloadManifest?
    @Published private(set) var verifiedModel: VerifiedModel?
    @Published private(set) var isDownloading = false
    @Published private(set) var statusMessage = "No model manifest selected. Existing local models remain available."

    private let service: ModelDownloadService

    init(service: ModelDownloadService = ModelDownloadService()) {
        self.service = service
    }

    func chooseManifest() {
        guard !isDownloading else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["json"]
        panel.prompt = "Select Manifest"
        panel.message = "Choose a local version-1 manifest with pinned HTTPS model URLs, byte counts, and SHA-256 hashes."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let access = SecurityScopedModelAccess(url: url)
        do {
            let data = try withExtendedLifetime(access) {
                try Data(contentsOf: url, options: [.mappedIfSafe])
            }
            guard data.count <= ModelDownloadManifest.maximumManifestBytes else {
                throw ModelDownloadError.invalidManifest
            }
            manifest = try JSONDecoder().decode(ModelDownloadManifest.self, from: data).validated()
            verifiedModel = nil
            statusMessage = "Manifest verified. Review its model and choose Download & Verify; nothing has downloaded yet."
        } catch {
            manifest = nil
            verifiedModel = nil
            statusMessage = (error as? ModelDownloadError)?.errorDescription
                ?? "The selected manifest could not be decoded. No download was started."
        }
    }

    func downloadAndVerify() async {
        guard let manifest, !isDownloading else { return }
        isDownloading = true
        statusMessage = "Downloading only from the manifest's HTTPS URLs. Clipboard and inference remain local."
        defer { isDownloading = false }
        do {
            let readiness = ModelReadiness.current(
                requiredRAMBytes: manifest.minimumUnifiedRAMBytes
            )
            verifiedModel = try await service.install(manifest: manifest, readiness: readiness)
            statusMessage = "Every file matched its declared size and SHA-256. The verified local model is ready to load."
        } catch {
            verifiedModel = nil
            statusMessage = (error as? ModelDownloadError)?.errorDescription
                ?? "Model acquisition failed. No partial model was installed."
        }
    }
}
