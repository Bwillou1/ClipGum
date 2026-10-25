import Foundation

/// Phase 2's deterministic Stage 1 and Phase 1 compatibility pipeline.
///
/// This type has no mutable state, performs no I/O, and never consults a model.
/// URL cleaning runs first so the redaction stage also sees URL-embedded secrets.
struct RuleCleaningService {
    static let redactionPlaceholder = "[SECRET_REDACTED]"

    private let urlCleaner = URLTrackingCleaner()
    private let secretRedactor = SecretRedactor(placeholder: RuleCleaningService.redactionPlaceholder)

    init() {}

    func clean(_ input: String) -> CleaningResult {
        let urlResult = urlCleaner.stripTrackingParameters(in: input)
        let redactionResult = secretRedactor.redactSecrets(in: urlResult.output)

        return CleaningResult(
            original: input,
            cleaned: redactionResult.output,
            removedTrackingParameters: urlResult.changeCount,
            redactedSecrets: redactionResult.changeCount
        )
    }

    func cleanURLs(_ input: String) -> CleaningResult {
        let result = urlCleaner.stripTrackingParameters(in: input)
        return CleaningResult(
            original: input,
            cleaned: result.output,
            removedTrackingParameters: result.changeCount,
            redactedSecrets: 0
        )
    }

    func scrubSecrets(_ input: String) -> CleaningResult {
        let result = secretRedactor.redactSecrets(in: input)
        return CleaningResult(
            original: input,
            cleaned: result.output,
            removedTrackingParameters: 0,
            redactedSecrets: result.changeCount
        )
    }

    func stripURLTracking(from input: String) -> String {
        urlCleaner.stripTrackingParameters(in: input).output
    }

    func redactSecrets(from input: String) -> String {
        secretRedactor.redactSecrets(in: input).output
    }
}
