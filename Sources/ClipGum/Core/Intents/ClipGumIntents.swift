import AppIntents
import ClipGumCore
import Foundation

@available(macOS 14.0, *)
struct SanitizeTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Sanitize Text"
    static let description = IntentDescription("Strip tracking parameters and redact secrets locally without opening ClipGum UI.")
    static let openAppWhenRun = false

    @Parameter(title: "Text") var text: String
    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: DeterministicTransforms.sanitize(text).output)
    }
}

@available(macOS 14.0, *)
struct ExtractTableIntent: AppIntent {
    static let title: LocalizedStringResource = "Extract Table"
    static let description = IntentDescription("Normalize a CSV, TSV, or semicolon-delimited selection into CSV using a deterministic parser.")
    static let openAppWhenRun = false

    @Parameter(title: "Text") var text: String
    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: try DeterministicTransforms.extractTable(text))
    }
}

@available(macOS 14.0, *)
struct RedactSecretsIntent: AppIntent {
    static let title: LocalizedStringResource = "Redact Secrets"
    static let description = IntentDescription("Redact API keys, tokens, internal hostnames, and IP addresses without network access.")
    static let openAppWhenRun = false

    @Parameter(title: "Text") var text: String
    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: DeterministicTransforms.redactSecrets(in: text).output)
    }
}

@available(macOS 14.0, *)
struct TransformWithLocalModelIntent: AppIntent {
    static let title: LocalizedStringResource = "Transform with Local Model"
    static let description = IntentDescription("Transform text through the explicitly selected on-device model. No cloud inference or clipboard read is performed.")
    static let openAppWhenRun = false

    @Parameter(title: "Text") var text: String
    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: try await LocalModelIntentBridge.shared.transform(text))
    }
}

/// URLs are safe Spotlight/deep-link entry points: they select a settings
/// surface only and never contain clipboard or transformed content.
enum ClipGumDeepLink {
    static let scheme = "clipgum"
    static let activityType = "com.clipgum.ClipGum.deep-link"

    enum Destination: String, Equatable {
        case rules
        case privacy
        case enterprise
    }

    static func destination(for url: URL) -> Destination? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        return Destination(rawValue: url.host?.lowercased() ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}
