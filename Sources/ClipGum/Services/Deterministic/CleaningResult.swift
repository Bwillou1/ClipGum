import Foundation

/// The complete, immutable input/output pair shown by the preview UI.
struct CleaningResult: Equatable, Sendable {
    let original: String
    let cleaned: String
    let removedTrackingParameters: Int
    let redactedSecrets: Int
    let pasteboardPayload: PasteboardPayload?

    init(
        original: String,
        cleaned: String,
        removedTrackingParameters: Int,
        redactedSecrets: Int,
        pasteboardPayload: PasteboardPayload? = nil
    ) {
        self.original = original
        self.cleaned = cleaned
        self.removedTrackingParameters = removedTrackingParameters
        self.redactedSecrets = redactedSecrets
        self.pasteboardPayload = pasteboardPayload
    }

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
