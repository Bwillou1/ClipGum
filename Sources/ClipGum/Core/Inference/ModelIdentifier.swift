import Foundation

struct ModelIdentifier: Equatable, Sendable {
    static let defaultHuggingFaceRepo = "prism-ml/bonsai-image-ternary-4B-mlx-2bit"

    let backend: InferenceBackendKind
    let localURL: URL
    let rawValue: String
    let repoOrModelName: String?
    let endpointURL: URL?
    let apiKey: String?

    init?(rawValue: String) {
        self.rawValue = rawValue

        if rawValue.hasPrefix("mlx:") {
            let path = String(rawValue.dropFirst("mlx:".count))
            guard path.hasPrefix("/"), !path.isEmpty, !path.contains("\0") else {
                return nil
            }
            self.backend = .mlx
            self.localURL = URL(fileURLWithPath: path, isDirectory: true)
            self.repoOrModelName = nil
            self.endpointURL = nil
            self.apiKey = nil
        } else if rawValue.hasPrefix("gguf:") {
            let path = String(rawValue.dropFirst("gguf:".count))
            guard path.hasPrefix("/"), !path.isEmpty, !path.contains("\0") else {
                return nil
            }
            self.backend = .gguf
            self.localURL = URL(fileURLWithPath: path, isDirectory: false)
            self.repoOrModelName = nil
            self.endpointURL = nil
            self.apiKey = nil
        } else if rawValue.hasPrefix("hf:") {
            var repo = String(rawValue.dropFirst("hf:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if repo.hasPrefix("https://huggingface.co/") {
                repo = String(repo.dropFirst("https://huggingface.co/".count))
            } else if repo.hasPrefix("http://huggingface.co/") {
                repo = String(repo.dropFirst("http://huggingface.co/".count))
            } else if repo.hasPrefix("https://hf.co/") {
                repo = String(repo.dropFirst("https://hf.co/".count))
            }
            repo = repo.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !repo.isEmpty, repo.contains("/"), !repo.contains("\0") else {
                return nil
            }
            self.backend = .mlx
            self.localURL = URL(fileURLWithPath: "/dev/null")
            self.repoOrModelName = repo
            self.endpointURL = nil
            self.apiKey = nil
        } else if rawValue.hasPrefix("api:") {
            let payload = String(rawValue.dropFirst("api:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = payload.components(separatedBy: "#")
            guard let first = parts.first, let url = URL(string: first) else {
                return nil
            }
            self.backend = .api
            self.localURL = URL(fileURLWithPath: "/dev/null")
            self.endpointURL = url
            self.repoOrModelName = parts.count > 1 && !parts[1].isEmpty ? parts[1] : "default"
            self.apiKey = parts.count > 2 && !parts[2].isEmpty ? parts[2] : nil
        } else {
            return nil
        }
    }

    static func mlx(directory: URL) -> String {
        "mlx:\(directory.path)"
    }

    static func gguf(file: URL) -> String {
        "gguf:\(file.path)"
    }

    static func hf(repoOrURL: String) -> String {
        var clean = repoOrURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("https://huggingface.co/") {
            clean = String(clean.dropFirst("https://huggingface.co/".count))
        } else if clean.hasPrefix("https://hf.co/") {
            clean = String(clean.dropFirst("https://hf.co/".count))
        }
        return "hf:\(clean)"
    }

    static func api(endpoint: String, model: String = "default", key: String = "") -> String {
        if key.isEmpty {
            return "api:\(endpoint)#\(model)"
        } else {
            return "api:\(endpoint)#\(model)#\(key)"
        }
    }
}
