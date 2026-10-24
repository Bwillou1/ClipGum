import Foundation

/// A local text-generation boundary. Implementations must not perform network
/// inference or mutate the pasteboard. `prompt` is the system instruction and
/// `input` is untrusted user data; they are deliberately separate arguments.
protocol InferenceEngine: AnyObject, Sendable {
    func loadModel(identifier: String) async throws
    func transform(
        prompt: String,
        input: String,
        maxTokens: Int
    ) async throws -> AsyncThrowingStream<String, Error>
}

/// Lifecycle operations are separate from the required generation interface so
/// pipeline tests can use a small mock while the app retains strict unloading.
protocol ManagedInferenceEngine: InferenceEngine {
    func unloadModel() async throws
    func updateConfiguration(_ configuration: InferenceConfiguration) async
}

enum InferenceBackendKind: String, Sendable {
    case mlx = "MLX"
    case gguf = "GGUF"
}

enum InferenceRuntimeStatus: Equatable, Sendable {
    case idle
    case loading(InferenceBackendKind)
    case ready(InferenceBackendKind, residentBytes: UInt64?)
    case generating(InferenceBackendKind, residentBytes: UInt64?)
    case unloading
    case failed(String)
}

struct InferenceConfiguration: Equatable, Sendable {
    static let absoluteOutputTokenLimit = 512

    /// Low-temperature editing, clamped to the Phase 2 contract.
    var temperature: Float
    /// Per-request hard cap. The engine clamps again even for a buggy caller.
    var maximumOutputTokens: Int
    var idleUnloadTimeout: TimeInterval
    var maximumInputUTF8Bytes: Int
    var contextTokens: Int
    var mlxMemoryLimitBytes: Int
    var mlxCacheLimitBytes: Int
    var maximumModelFileBytes: Int64

    init(
        temperature: Float = 0.2,
        maximumOutputTokens: Int = 256,
        idleUnloadTimeout: TimeInterval = 5 * 60,
        maximumInputUTF8Bytes: Int = 32_768,
        contextTokens: Int = 4_096,
        mlxMemoryLimitBytes: Int = 6 * 1_024 * 1_024 * 1_024,
        mlxCacheLimitBytes: Int = 256 * 1_024 * 1_024,
        maximumModelFileBytes: Int64 = 8 * 1_024 * 1_024 * 1_024
    ) {
        self.temperature = temperature.isFinite ? min(0.3, max(0.1, temperature)) : 0.2
        self.maximumOutputTokens = min(
            Self.absoluteOutputTokenLimit,
            max(1, maximumOutputTokens)
        )
        self.idleUnloadTimeout = idleUnloadTimeout.isFinite
            ? min(3_600, max(0.05, idleUnloadTimeout))
            : 5 * 60
        self.maximumInputUTF8Bytes = min(262_144, max(1_024, maximumInputUTF8Bytes))
        self.contextTokens = min(16_384, max(1_024, contextTokens))
        self.mlxMemoryLimitBytes = max(512 * 1_024 * 1_024, mlxMemoryLimitBytes)
        self.mlxCacheLimitBytes = max(0, mlxCacheLimitBytes)
        self.maximumModelFileBytes = max(512 * 1_024 * 1_024, maximumModelFileBytes)
    }

    func boundedTokens(_ requested: Int) -> Int {
        min(maximumOutputTokens, max(1, requested))
    }

    var maximumOutputUTF8Bytes: Int {
        // A token can decode to multiple bytes; input-sized edits also need room.
        // This is a second, independent allocation guard beyond token counting.
        min(4 * 1_024 * 1_024, max(16_384, maximumInputUTF8Bytes * 4 + 4_096))
    }
}

enum InferenceEngineError: LocalizedError, Equatable {
    case invalidIdentifier
    case invalidModel
    case modelTooLarge
    case modelNotLoaded
    case engineBusy
    case unsupportedArchitecture
    case inputTooLarge
    case contextLimit
    case outputTooLarge
    case outOfMemory
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .invalidIdentifier:
            return "The local model identifier is invalid. Choose an MLX folder or GGUF file again."
        case .invalidModel:
            return "The selected model is missing required files or could not be initialized."
        case .modelTooLarge:
            return "The selected model exceeds ClipGum's configured local model size boundary."
        case .modelNotLoaded:
            return "No local model is loaded. Choose a model from the ClipGum menu first."
        case .engineBusy:
            return "A local transformation is already running. Cancel it before changing models."
        case .unsupportedArchitecture:
            return "Phase 2 local inference requires an Apple Silicon Mac."
        case .inputTooLarge:
            return "The input exceeds the local inference memory boundary. Shorten it and try again."
        case .contextLimit:
            return "The prompt and requested output exceed the model context boundary."
        case .outputTooLarge:
            return "The model exceeded the bounded output budget. Its partial output was discarded."
        case .outOfMemory:
            return "The local model ran out of memory. Partial output was discarded and the model was unloaded."
        case .generationFailed:
            return "Local inference failed. Partial model output was discarded."
        }
    }
}

enum InferenceErrorClassifier {
    static func classify(_ error: Error) -> Error {
        if error is CancellationError {
            return error
        }
        if let engineError = error as? InferenceEngineError {
            return engineError
        }

        let description = String(describing: error).lowercased()
        let nsDescription = (error as NSError).localizedDescription.lowercased()
        let combined = description + " " + nsDescription
        if combined.contains("out of memory")
            || combined.contains("memory limit")
            || combined.contains("cannot allocate")
            || combined.contains("failed to allocate")
            || combined.contains("allocation failed")
        {
            return InferenceEngineError.outOfMemory
        }
        return InferenceEngineError.generationFailed
    }
}
