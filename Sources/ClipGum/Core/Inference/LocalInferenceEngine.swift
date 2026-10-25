import ClipGumCore
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
    private var lifecycleOperationActive = false
    private var nextGenerationID = 0
    private var activityVersion = 0
    private let memoryCompactor = MemoryCompactor()
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
        guard activeGeneration == nil, !lifecycleOperationActive else {
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

        lifecycleOperationActive = true
        defer { lifecycleOperationActive = false }
        memoryCompactor.cancel()
        activityVersion += 1
        if let oldBackend = backend {
            emit(.unloading)
            do {
                try await oldBackend.unloadModel()
            } catch {
                let classified = InferenceErrorClassifier.classify(error)
                emitFailure(for: classified)
                throw classified
            }
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
        guard activeGeneration == nil, !lifecycleOperationActive else {
            throw InferenceEngineError.engineBusy
        }
        guard let backend, let backendKind else {
            throw InferenceEngineError.modelNotLoaded
        }
        guard prompt.utf8.count + input.utf8.count <= configuration.maximumInputUTF8Bytes else {
            throw InferenceEngineError.inputTooLarge
        }

        memoryCompactor.cancel()
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
            let classified = InferenceErrorClassifier.classify(error)
            if let engineError = classified as? InferenceEngineError,
                engineError == .outOfMemory
            {
                // Keep the generation busy across cleanup so no new request can
                // enter a backend that is being torn down after an OOM.
                try? await backend.unloadModel()
                self.backend = nil
                self.backendKind = nil
                loadedIdentifier = nil
                activeGeneration = nil
                emitFailure(for: classified)
            } else {
                activeGeneration = nil
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
            continuation.onTermination = { termination in
                // `.finished` is not consumer cancellation. Do not cancel the
                // task before it has finalized status, configuration, or OOM
                // teardown; a cancelled/deallocated consumer still stops decode.
                if case .cancelled = termination {
                    task.cancel()
                }
            }
        }
    }

    func unloadModel() async throws {
        guard activeGeneration == nil, !lifecycleOperationActive else {
            throw InferenceEngineError.engineBusy
        }
        lifecycleOperationActive = true
        defer { lifecycleOperationActive = false }
        memoryCompactor.cancel()
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
        guard activeGeneration == nil, !lifecycleOperationActive else {
            return
        }
        lifecycleOperationActive = true
        await backend?.updateConfiguration(configuration)
        lifecycleOperationActive = false
        if backend != nil {
            scheduleIdleUnload()
        }
    }

    private func finishGeneration(_ generationID: Int, failure: Error?) async {
        guard activeGeneration == generationID else {
            return
        }
        activityVersion += 1

        if let engineError = failure as? InferenceEngineError,
            engineError == .outOfMemory,
            let failedBackend = backend
        {
            try? await failedBackend.unloadModel()
            backend = nil
            backendKind = nil
            loadedIdentifier = nil
            activeGeneration = nil
            emitFailure(for: engineError)
            return
        }

        if let backend, let backendKind {
            await backend.updateConfiguration(configuration)
            activeGeneration = nil
            emitReady(kind: backendKind)
            scheduleIdleUnload()
        } else {
            activeGeneration = nil
            emit(.idle)
        }
    }

    private func scheduleIdleUnload() {
        memoryCompactor.cancel()
        guard backend != nil, activeGeneration == nil else {
            return
        }
        let version = activityVersion
        let timeout = configuration.idleUnloadTimeout
        memoryCompactor.schedule(after: timeout) { [weak self] in
            await self?.unloadIfIdle(version: version)
        }
    }

    private func unloadIfIdle(version: Int) async {
        guard version == activityVersion, activeGeneration == nil,
            !lifecycleOperationActive, let backend
        else {
            return
        }
        lifecycleOperationActive = true
        defer { lifecycleOperationActive = false }
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
