import Foundation

/// iOS/iPadOS-facing adapter over the same deterministic core used by the CLI
/// and macOS App Intents. It has no pasteboard, extension-context, or I/O read.
public struct MobileCleaningService: Sendable {
    public init() {}

    public func clean(_ input: String) -> CoreTransformResult {
        DeterministicTransforms.sanitize(input)
    }

    public func scrubSecrets(_ input: String) -> CoreTransformResult {
        DeterministicTransforms.redactSecrets(in: input)
    }

    public func stripURLTracking(_ input: String) -> CoreTransformResult {
        DeterministicTransforms.stripTrackingParameters(in: input)
    }

    public func extractTable(_ input: String) throws -> String {
        try DeterministicTransforms.extractTable(input)
    }
}
