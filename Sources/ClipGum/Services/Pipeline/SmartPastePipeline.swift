import Foundation

struct TransformationResult: Equatable, Sendable {
    let original: String
    let deterministicBaseline: CleaningResult
    let action: SmartPasteAction
    let output: String
    let validation: ValidationReport
    let streamedChunks: Int
}

enum PipelineEvent: Equatable, Sendable {
    case chunk(String)
    case completed(TransformationResult)
}

enum SmartPastePipelineError: LocalizedError, Equatable {
    case mechanicalActionRequiresSynchronousPath

    var errorDescription: String? {
        "This action is deterministic and must not be sent to an inference engine."
    }
}

/// Stage 1 is synchronous and engine-free. Stage 2 is always explicitly chosen,
/// receives only Stage 1's cleaned text, and validates before emitting a result.
struct SmartPastePipeline {
    private let engine: any InferenceEngine
    private let cleaner: RuleCleaningService
    private let jsonTooling: JSONToolingService
    private let typeScriptGenerator: TypeScriptGenerator
    private let logScrubber: LogScrubber
    private let bashInspector: BashInspector
    private let shareReadySession: ShareReadySession
    private let sanitizer: OutputSanitizer
    private let validator: OutputValidator
    private let configuration: InferenceConfiguration

    init(
        engine: any InferenceEngine,
        cleaner: RuleCleaningService = RuleCleaningService(),
        jsonTooling: JSONToolingService = JSONToolingService(),
        typeScriptGenerator: TypeScriptGenerator = TypeScriptGenerator(),
        logScrubber: LogScrubber = LogScrubber(),
        bashInspector: BashInspector = BashInspector(),
        shareReadySession: ShareReadySession = ShareReadySession(),
        sanitizer: OutputSanitizer = OutputSanitizer(),
        validator: OutputValidator = OutputValidator(),
        configuration: InferenceConfiguration = InferenceConfiguration()
    ) {
        self.engine = engine
        self.cleaner = cleaner
        self.jsonTooling = jsonTooling
        self.typeScriptGenerator = typeScriptGenerator
        self.logScrubber = logScrubber
        self.bashInspector = bashInspector
        self.shareReadySession = shareReadySession
        self.sanitizer = sanitizer
        self.validator = validator
        self.configuration = configuration
    }

    /// Returns nil only for an LLM action. There is no engine call on this path.
    func mechanicalResult(
        action: SmartPasteAction,
        input: String,
        options: DeveloperActionOptions = DeveloperActionOptions()
    ) throws -> CleaningResult? {
        let output: String
        let redactionCount: Int
        switch action {
        case .clean:
            return cleaner.clean(input)
        case .urlClean:
            return cleaner.cleanURLs(input)
        case .secretScrub:
            return cleaner.scrubSecrets(input)
        case .shareReady:
            let result = shareReadySession.anonymize(input)
            output = result.output
            redactionCount = result.replacementCount
        case .restoreIdentifiers:
            let result = shareReadySession.restore(input)
            output = result.output
            redactionCount = 0
        case .formatJSON:
            output = try jsonTooling.format(input, indentation: options.jsonIndentation)
            redactionCount = 0
        case .minifyJSON:
            output = try jsonTooling.minify(input)
            redactionCount = 0
        case .jsonToTypeScript:
            output = try typeScriptGenerator.generate(
                input: input,
                options: TypeScriptGenerationOptions(
                    rootName: options.typeScriptRootName,
                    includesExport: options.typeScriptIncludesExport
                )
            )
            redactionCount = 0
        case .scrubLogs:
            let result = logScrubber.scrub(input)
            output = result.output
            redactionCount = result.redactedSecrets
        case .inspectBash:
            output = bashInspector.report(bashInspector.inspect(input))
            redactionCount = 0
        case .explainBash, .correction, .rewrite, .tableToCSV:
            return nil
        }
        return CleaningResult(
            original: input,
            cleaned: output,
            removedTrackingParameters: 0,
            redactedSecrets: redactionCount
        )
    }

    func inferenceStream(
        action: SmartPasteAction,
        input: String,
        maxTokens: Int
    ) async throws -> AsyncThrowingStream<PipelineEvent, Error> {
        guard !action.isMechanical else {
            throw SmartPastePipelineError.mechanicalActionRequiresSynchronousPath
        }
        guard input.utf8.count <= configuration.maximumInputUTF8Bytes else {
            throw InferenceEngineError.inputTooLarge
        }

        let baseline = cleaner.clean(input)
        // C chat templates use NUL-terminated strings. Reject rather than
        // silently losing a suffix; deterministic actions remain available.
        guard !baseline.cleaned.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw InferenceEngineError.invalidInput
        }
        let template = PromptTemplate(action: action)
        let boundedTokens = min(
            InferenceConfiguration.absoluteOutputTokenLimit,
            max(1, maxTokens)
        )
        let engineStream = try await engine.transform(
            prompt: template.instructions,
            input: baseline.cleaned,
            maxTokens: boundedTokens
        )
        let maximumOutputBytes = configuration.maximumOutputUTF8Bytes

        return AsyncThrowingStream { continuation in
            let task = Task {
                var rawOutput = ""
                var outputBytes = 0
                var chunkCount = 0
                do {
                    for try await delta in engineStream {
                        try Task.checkCancellation()
                        guard delta.utf8.count <= maximumOutputBytes - outputBytes else {
                            throw InferenceEngineError.outputTooLarge
                        }
                        rawOutput += delta
                        outputBytes += delta.utf8.count
                        chunkCount += 1
                        continuation.yield(.chunk(delta))
                    }

                    let output = sanitizer.sanitize(
                        action: action,
                        source: baseline.cleaned,
                        output: rawOutput
                    )
                    let report = validator.validate(
                        action: action,
                        source: baseline.cleaned,
                        output: output
                    )
                    continuation.yield(.completed(TransformationResult(
                        original: input,
                        deterministicBaseline: baseline,
                        action: action,
                        output: output,
                        validation: report,
                        streamedChunks: chunkCount
                    )))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: InferenceErrorClassifier.classify(error))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
