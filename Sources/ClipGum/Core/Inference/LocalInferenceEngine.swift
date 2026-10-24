import Foundation

/// Backend selection, generation serialization, status updates, and idle offload.
/// No clipboard values appear in status or errors crossing this boundary.
actor LocalInferenceEngine: ManagedInferenceEngine {
    typealias BackendFactory = @Sendable (InferenceConfiguration) -> any ManagedInferenceEngine
    typealias StatusHandler = @Sendable (InferenceRuntimeStatus) -> Void

    private var configuration: InferenceConfiguration
    private let mlxFactory: BackendFactory
    private let ggufFactory: BackendFactory

    private var backend: (any ManagedInferenceEngine)?
    private var backendKind: InferenceBackendKind?
    private var loadedIdentifier: String?
    private var activeGeneration: Int?
    private var nextGenerationID = 0
    private var activityVersion = 0
    private var idleTask: Task<Void, Never>?
    private var status: InferenceRuntimeStatus = .idle
    private var statusHandler: StatusHandler?

    init(
        configuration: InferenceConfiguration,
        mlxFactory: @escaping BackendFactory = { MLXInferenceEngine(configuration: $0) },
        ggufFactory: @escaping BackendFactory = { GGUFInferenceEngine(configuration: $0) }
    ) {
        self.configuration = configuration
        self.mlxFactory = mlxFactory
        self.ggufFactory = ggufFactory
    }

    func setStatusHandler(_ handler: @escaping StatusHandler) {
        statusHandler = handler
        handler(status)
    }

    func loadModel(identifier: String) async throws {
        guard activeGeneration == nil else {
            throw InferenceEngineError.engineBusy
        }
        guard let modelIdentifier = ModelIdentifier(rawValue: identifier) else {
            emit(.failed("Invalid local model identifier"))
            throw InferenceEngineError.invalidIdentifier
        }
        if loadedIdentifier == identifier, backend != nil, let backendKind {
            emitReady(kind: backendKind)
            scheduleIdleUnload()
            return
        }

        idleTask?.cancel()
        activityVersion += 1
        if let oldBackend = backend {
            emit(.unloading)
            try await oldBackend.unloadModel()
            backend = nil
            backendKind = nil
            loadedIdentifier = nil
        }

        let kind = modelIdentifier.backend
        emit(.loading(kind))
        let newBackend = kind == .mlx
            ? mlxFactory(configuration)
            : ggufFactory(configuration)
        do {
            try await newBackend.loadModel(identifier: identifier)
            backend = newBackend
            backendKind = kind
            loadedIdentifier = identifier
            emitReady(kind: kind)
            scheduleIdleUnload()
        } catch {
            try? await newBackend.unloadModel()
            backend = nil
            backendKind = nil
            loadedIdentifier = nil
            let classified = InferenceErrorClassifier.classify(error)
            emitFailure(for: classified)
            throw classified
        }
    }

    func transform(
        prompt: String,
        input: String,
        maxTokens: Int
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard activeGeneration == nil else {
            throw InferenceEngineError.engineBusy
        }
        guard let backend, let backendKind else {
            throw InferenceEngineError.modelNotLoaded
        }
        guard prompt.utf8.count + input.utf8.count <= configuration.maximumInputUTF8Bytes else {
            throw InferenceEngineError.inputTooLarge
        }

        idleTask?.cancel()
        nextGenerationID += 1
        let generationID = nextGenerationID
        activeGeneration = generationID
        emit(.generating(backendKind, residentBytes: ProcessMemoryUsage.residentBytes()))

        let boundedTokens = configuration.boundedTokens(maxTokens)
        let baseStream: AsyncThrowingStream<String, Error>
        do {
            baseStream = try await backend.transform(
                prompt: prompt,
                input: input,
                maxTokens: boundedTokens
            )
        } catch {
            activeGeneration = nil
            let classified = InferenceErrorClassifier.classify(error)
            if let engineError = classified as? InferenceEngineError,
                engineError == .outOfMemory
            {
                try? await backend.unloadModel()
                self.backend = nil
                self.backendKind = nil
                loadedIdentifier = nil
                emitFailure(for: classified)
            } else {
                emitReady(kind: backendKind)
                scheduleIdleUnload()
            }
            throw classified
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                var failure: Error?
                do {
                    for try await chunk in baseStream {
                        try Task.checkCancellation()
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    let classified = InferenceErrorClassifier.classify(error)
                    failure = classified
                    continuation.finish(throwing: classified)
                }
                await self.finishGeneration(generationID, failure: failure)
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func unloadModel() async throws {
        guard activeGeneration == nil else {
            throw InferenceEngineError.engineBusy
        }
        idleTask?.cancel()
        activityVersion += 1
        guard let backend else {
            loadedIdentifier = nil
            backendKind = nil
            emit(.idle)
            return
        }

        emit(.unloading)
        do {
            try await backend.unloadModel()
            self.backend = nil
            backendKind = nil
            loadedIdentifier = nil
            emit(.idle)
        } catch {
            let classified = InferenceErrorClassifier.classify(error)
            emitFailure(for: classified)
            throw classified
        }
    }

    func updateConfiguration(_ configuration: InferenceConfiguration) async {
        self.configuration = configuration
        if activeGeneration == nil {
            await backend?.updateConfiguration(configuration)
            if backend != nil {
                scheduleIdleUnload()
            }
        }
    }

    private func finishGeneration(_ generationID: Int, failure: Error?) async {
        guard activeGeneration == generationID else {
            return
        }
        activeGeneration = nil
        activityVersion += 1

        if let engineError = failure as? InferenceEngineError,
            engineError == .outOfMemory,
            let failedBackend = backend
        {
            try? await failedBackend.unloadModel()
            backend = nil
            backendKind = nil
            loadedIdentifier = nil
            emitFailure(for: engineError)
            return
        }

        if let backend, let backendKind {
            await backend.updateConfiguration(configuration)
            emitReady(kind: backendKind)
            scheduleIdleUnload()
        } else {
            emit(.idle)
        }
    }

    private func scheduleIdleUnload() {
        idleTask?.cancel()
        guard backend != nil, activeGeneration == nil else {
            return
        }
        let version = activityVersion
        let timeout = configuration.idleUnloadTimeout
        idleTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            } catch {
                return
            }
            await self?.unloadIfIdle(version: version)
        }
    }

    private func unloadIfIdle(version: Int) async {
        guard version == activityVersion, activeGeneration == nil, let backend else {
            return
        }
        emit(.unloading)
        try? await backend.unloadModel()
        self.backend = nil
        backendKind = nil
        loadedIdentifier = nil
        activityVersion += 1
        emit(.idle)
    }

    private func emitReady(kind: InferenceBackendKind) {
        emit(.ready(kind, residentBytes: ProcessMemoryUsage.residentBytes()))
    }

    private func emitFailure(for error: Error) {
        if let engineError = error as? InferenceEngineError {
            switch engineError {
            case .outOfMemory:
                emit(.failed("Out of memory · Model unloaded"))
            case .unsupportedArchitecture:
                emit(.failed("Apple Silicon required"))
            default:
                emit(.failed("Model unavailable · Deterministic actions ready"))
            }
        } else if error is CancellationError {
            emit(.idle)
        } else {
            emit(.failed("Model unavailable · Deterministic actions ready"))
        }
    }

    private func emit(_ newStatus: InferenceRuntimeStatus) {
        status = newStatus
        statusHandler?(newStatus)
    }
}
