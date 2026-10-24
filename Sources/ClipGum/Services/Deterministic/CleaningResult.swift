import Foundation

/// The complete, immutable input/output pair shown by the preview UI.
struct CleaningResult: Equatable, Sendable {
    let original: String
    let cleaned: String
    let removedTrackingParameters: Int
    let redactedSecrets: Int

    var hasChanges: Bool {
        original != cleaned
    }
}

struct TransformResult: Equatable, Sendable {
    let output: String
    let changeCount: Int

    init(output: String, changeCount: Int) {
        self.output = output
        self.changeCount = changeCount
    }
}
