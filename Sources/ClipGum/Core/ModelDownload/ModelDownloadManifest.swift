import Foundation

enum ModelManifestBackend: String, Codable, Sendable {
    case mlx
    case gguf

    var inferenceBackend: InferenceBackendKind {
        switch self {
        case .mlx: return .mlx
        case .gguf: return .gguf
        }
    }
}

struct ModelDownloadManifest: Codable, Equatable, Sendable {
    static let maximumManifestBytes = 1_048_576
    static let maximumTotalBytes: Int64 = 8 * 1_024 * 1_024 * 1_024

    let formatVersion: Int
    let identifier: String
    let displayName: String
    let backend: ModelManifestBackend
    let minimumUnifiedRAMBytes: UInt64
    let files: [ModelDownloadFile]

    func validated() throws -> ModelDownloadManifest {
        guard formatVersion == 1 else { throw ModelDownloadError.invalidManifest }
        guard Self.isSafeComponent(identifier), identifier.utf8.count <= 128 else {
            throw ModelDownloadError.invalidManifest
        }
        guard
            !displayName.isEmpty,
            displayName.utf8.count <= 120,
            !displayName.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
        else {
            throw ModelDownloadError.invalidManifest
        }
        guard !files.isEmpty, files.count <= 64 else {
            throw ModelDownloadError.invalidManifest
        }
        var names = Set<String>()
        var total: Int64 = 0
        for file in files {
            guard
                Self.isSafeComponent(file.name),
                file.name.utf8.count <= 255,
                names.insert(file.name).inserted,
                HTTPSURLPolicy.isValid(file.url),
                file.expectedBytes > 0,
                file.sha256.count == 64,
                file.sha256.utf8.allSatisfy({ scalar in
                    (48...57).contains(Int(scalar)) || (65...70).contains(Int(scalar)) || (97...102).contains(Int(scalar))
                })
            else {
                throw ModelDownloadError.invalidManifest
            }
            let nextTotal = total.addingReportingOverflow(file.expectedBytes)
            guard !nextTotal.overflow else { throw ModelDownloadError.modelTooLarge }
            total = nextTotal.partialValue
            guard total > 0, total <= Self.maximumTotalBytes else {
                throw ModelDownloadError.modelTooLarge
            }
        }
        switch backend {
        case .gguf:
            guard files.count == 1, files[0].name.lowercased().hasSuffix(".gguf") else {
                throw ModelDownloadError.invalidManifest
            }
        case .mlx:
            guard
                files.contains(where: { $0.name == "config.json" }),
                files.contains(where: { $0.name.lowercased().hasSuffix(".safetensors") })
            else {
                throw ModelDownloadError.invalidManifest
            }
        }
        return self
    }

    private static func isSafeComponent(_ value: String) -> Bool {
        guard
            !value.isEmpty,
            value != ".",
            value != "..",
            !value.contains("/"),
            !value.contains("\\"),
            !value.contains(":"),
            !value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
        else {
            return false
        }
        return true
    }
}

struct ModelDownloadFile: Codable, Equatable, Sendable {
    let name: String
    let url: URL
    let expectedBytes: Int64
    let sha256: String
}

enum ModelDownloadError: LocalizedError {
    case invalidManifest
    case modelTooLarge
    case insufficientMemory
    case downloadRejected
    case byteCountMismatch
    case digestMismatch
    case destinationExists
    case installationFailed

    var errorDescription: String? {
        switch self {
        case .invalidManifest:
            return "The model manifest is invalid. Use a version-1 manifest with safe filenames, HTTPS URLs, exact byte counts, and SHA-256 hashes."
        case .modelTooLarge:
            return "The verified model exceeds ClipGum's 8 GiB acquisition limit."
        case .insufficientMemory:
            return "This Mac does not meet the model's declared unified-memory requirement."
        case .downloadRejected:
            return "The model download was rejected or exceeded its declared size. No partial model was installed."
        case .byteCountMismatch:
            return "The downloaded model size does not match the manifest. No partial model was installed."
        case .digestMismatch:
            return "The downloaded model SHA-256 does not match the manifest. The tampered or corrupt payload was deleted."
        case .destinationExists:
            return "This model identifier is already installed. Choose its local weights or use a new versioned manifest."
        case .installationFailed:
            return "The verified model could not be installed atomically. No partial model was installed."
        }
    }
}
