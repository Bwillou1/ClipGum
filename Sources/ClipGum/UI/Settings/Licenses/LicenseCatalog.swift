import Foundation

struct LicenseEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let resourceName: String
    let resourceExtension: String
    let summary: String

    func loadText() -> String {
        guard
            let url = Bundle.module.url(
                forResource: resourceName,
                withExtension: resourceExtension
            ),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "The embedded license resource is unavailable. The distribution package is incomplete."
        }
        return text
    }
}

enum LicenseCatalog {
    static let entries: [LicenseEntry] = [
        entry("clipgum", "ClipGum", "ClipGum", "Apache-2.0"),
        entry("sparkle", "Sparkle 2.10.0", "Sparkle", "MIT · signed appcasts and updates"),
        entry("argument-parser", "Swift Argument Parser 1.5.0", "ArgumentParser", "Apache-2.0 · UNIX CLI parsing"),
        entry("argon2", "Argon2 Swift", "Argon2", "MIT · RFC 9106 local backup KDF"),
        entry("mlx", "MLX", "MLX", "MIT · Apple Silicon local inference"),
        entry("mlx-swift", "MLX Swift", "MLXSwift", "MIT"),
        entry("mlx-lm", "MLX Swift LM", "MLXLM", "MIT"),
        entry("llama-swift", "llama.swift", "LlamaSwift", "MIT · GGUF package boundary"),
        entry("llama-cpp", "llama.cpp", "LlamaCPP", "MIT · GGUF inference engine"),
        entry("boop", "Boop", "Boop", "MIT · supplied-text transformation reference"),
        entry("maccy", "Maccy", "Maccy", "MIT · pasteboard/menu-bar reference"),
        entry("prismml", "PrismML Ternary Bonsai", "PrismML", "External model attribution; no weights bundled"),
        entry("acknowledgments", "Acknowledgments", "Acknowledgments", "References and scope of attribution"),
        entry("sbom", "Software Bill of Materials", "SBOM", "CycloneDX 1.5 dependency inventory", "json")
    ]

    private static func entry(
        _ id: String,
        _ title: String,
        _ resource: String,
        _ summary: String,
        _ ext: String = "txt"
    ) -> LicenseEntry {
        LicenseEntry(
            id: id,
            title: title,
            resourceName: resource,
            resourceExtension: ext,
            summary: summary
        )
    }
}
