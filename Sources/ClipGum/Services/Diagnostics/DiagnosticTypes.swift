import Foundation

/// Closed vocabularies are intentional: callers cannot attach arbitrary names,
/// error descriptions, prompts, clipboard strings, mappings, or regex matches.
enum DiagnosticFeature: String, Codable, CaseIterable {
    case cleanedLink = "cleaned_link"
    case tableToCSV = "table_to_csv"
    case richTextSanitized = "rich_text_sanitized"
    case pdfArtifactsRepaired = "pdf_artifacts_repaired"
    case deterministicClean = "deterministic_clean"
    case secretScrubbed = "secret_scrubbed"
    case identifiersRestored = "identifiers_restored"
    case localRewrite = "local_rewrite"
    case correction = "correction"
    case professionalEmail = "professional_email"
    case slackSummary = "slack_summary"
    case jsonFormatted = "json_formatted"
    case jsonMinified = "json_minified"
    case typeScriptGenerated = "typescript_generated"
    case logScrubbed = "log_scrubbed"
    case bashInspected = "bash_inspected"
    case bashExplained = "bash_explained"
    case shareReady = "share_ready"

    init?(action: SmartPasteAction) {
        switch action {
        case .clean: self = .deterministicClean
        case .urlClean: self = .cleanedLink
        case .convertTable, .tableToCSV: self = .tableToCSV
        case .sanitizeRichText: self = .richTextSanitized
        case .repairPDF: self = .pdfArtifactsRepaired
        case .secretScrub: self = .secretScrubbed
        case .restoreIdentifiers: self = .identifiersRestored
        case .rewrite: self = .localRewrite
        case .correction: self = .correction
        case .professionalEmail: self = .professionalEmail
        case .slackSummary: self = .slackSummary
        case .formatJSON: self = .jsonFormatted
        case .minifyJSON: self = .jsonMinified
        case .jsonToTypeScript: self = .typeScriptGenerated
        case .scrubLogs: self = .logScrubbed
        case .inspectBash: self = .bashInspected
        case .explainBash: self = .bashExplained
        case .shareReady: self = .shareReady
        }
    }
}

enum DiagnosticErrorCode: String, Codable, CaseIterable {
    case invalidInput = "invalid_input"
    case outputLimit = "output_limit"
    case modelUnavailable = "model_unavailable"
    case modelOutOfMemory = "model_out_of_memory"
    case inferenceFailed = "inference_failed"
    case invariantBlocked = "invariant_blocked"
    case cancelled = "cancelled"
}

struct DiagnosticFeaturePayload: Codable, Equatable {
    let feature: DiagnosticFeature
    let activationCount: Int
    let p50LatencyMilliseconds: UInt64
    let p95LatencyMilliseconds: UInt64
}

struct DiagnosticErrorPayload: Codable, Equatable {
    let error: DiagnosticErrorCode
    let count: Int
}

struct DiagnosticPayload: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let features: [DiagnosticFeaturePayload]
    let errors: [DiagnosticErrorPayload]
    let peakResidentMemoryBytes: UInt64
}

struct DiagnosticFeatureMetrics: Equatable {
    var activationCount = 0
    var latencySamples: [UInt64] = []
}

struct DiagnosticsSnapshot: Equatable {
    let features: [DiagnosticFeature: DiagnosticFeatureMetrics]
    let errors: [DiagnosticErrorCode: Int]
    let peakResidentMemoryBytes: UInt64
}

enum DiagnosticPayloadSchema {
    private static let rootKeys: Set<String> = [
        "schemaVersion", "generatedAt", "features", "errors", "peakResidentMemoryBytes"
    ]
    private static let featureKeys: Set<String> = [
        "feature", "activationCount", "p50LatencyMilliseconds", "p95LatencyMilliseconds"
    ]
    private static let errorKeys: Set<String> = ["error", "count"]

    /// A second, independent payload gate. Even a future Codable edit cannot
    /// silently add a free-form diagnostic field without updating this schema
    /// and its tests. Strings are limited to generated timestamps and enums.
    static func validate(_ data: Data) throws {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any], Set(root.keys) == rootKeys else {
            throw DiagnosticPayloadError.unexpectedSchema
        }
        guard
            root["schemaVersion"] as? Int == 1,
            let generatedAt = root["generatedAt"] as? String,
            generatedAt.count == 20,
            ISO8601DateFormatter().date(from: generatedAt) != nil,
            root["peakResidentMemoryBytes"] as? NSNumber != nil,
            let features = root["features"] as? [[String: Any]],
            let errors = root["errors"] as? [[String: Any]]
        else {
            throw DiagnosticPayloadError.unexpectedSchema
        }
        for feature in features {
            guard
                Set(feature.keys) == featureKeys,
                let name = feature["feature"] as? String,
                DiagnosticFeature(rawValue: name) != nil,
                feature["activationCount"] as? NSNumber != nil,
                feature["p50LatencyMilliseconds"] as? NSNumber != nil,
                feature["p95LatencyMilliseconds"] as? NSNumber != nil
            else {
                throw DiagnosticPayloadError.unexpectedSchema
            }
        }
        for error in errors {
            guard
                Set(error.keys) == errorKeys,
                let name = error["error"] as? String,
                DiagnosticErrorCode(rawValue: name) != nil,
                error["count"] as? NSNumber != nil
            else {
                throw DiagnosticPayloadError.unexpectedSchema
            }
        }
    }
}

enum DiagnosticPayloadError: Error {
    case unexpectedSchema
}
