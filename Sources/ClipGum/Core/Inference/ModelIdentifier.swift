import Foundation

struct ModelIdentifier: Equatable, Sendable {
    let backend: InferenceBackendKind
    let localURL: URL

    init?(rawValue: String) {
        let prefix: String
        let backend: InferenceBackendKind
        if rawValue.hasPrefix("mlx:") {
            prefix = "mlx:"
            backend = .mlx
        } else if rawValue.hasPrefix("gguf:") {
            prefix = "gguf:"
            backend = .gguf
        } else {
            return nil
        }

        let path = String(rawValue.dropFirst(prefix.count))
        guard path.hasPrefix("/"), !path.isEmpty, !path.contains("\0") else {
            return nil
        }
        self.backend = backend
        self.localURL = URL(fileURLWithPath: path, isDirectory: backend == .mlx)
    }

    static func mlx(directory: URL) -> String {
        "mlx:\(directory.path)"
    }

    static func gguf(file: URL) -> String {
        "gguf:\(file.path)"
    }
}
