import Foundation
@testable import ClipGum

struct RecordedTransform: Equatable, Sendable {
    let prompt: String
    let input: String
    let maxTokens: Int
}

actor MockManagedInferenceEngine: ManagedInferenceEngine {
    private(set) var loadIdentifiers: [String] = []
    private(set) var transformCalls: [RecordedTransform] = []
    private(set) var unloadCallCount = 0
    private(set) var configurationUpdates: [InferenceConfiguration] = []

    private let chunks: [String]
    private let loadError: Error?
    private let transformError: Error?
    private let streamError: Error?
    private let streamDelayNanoseconds: UInt64

    init(
        chunks: [String] = [],
        loadError: Error? = nil,
        transformError: Error? = nil,
        streamError: Error? = nil,
        streamDelayNanoseconds: UInt64 = 0
    ) {
        self.chunks = chunks
        self.loadError = loadError
        self.transformError = transformError
        self.streamError = streamError
        self.streamDelayNanoseconds = streamDelayNanoseconds
    }

    func loadModel(identifier: String) async throws {
        loadIdentifiers.append(identifier)
        if let loadError {
            throw loadError
        }
    }

    func transform(
        prompt: String,
        input: String,
        maxTokens: Int
    ) async throws -> AsyncThrowingStream<String, Error> {
        transformCalls.append(RecordedTransform(
            prompt: prompt,
            input: input,
            maxTokens: maxTokens
        ))
        if let transformError {
            throw transformError
        }
        let chunks = self.chunks
        let streamError = self.streamError
        let delay = streamDelayNanoseconds
        return AsyncThrowingStream { continuation in
            let task = Task {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                for chunk in chunks {
                    if Task.isCancelled {
                        continuation.finish(throwing: CancellationError())
                        return
                    }
                    continuation.yield(chunk)
                }
                continuation.finish(throwing: streamError)
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func unloadModel() async throws {
        unloadCallCount += 1
    }

    func updateConfiguration(_ configuration: InferenceConfiguration) async {
        configurationUpdates.append(configuration)
    }
}

final class InferenceStatusRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [InferenceRuntimeStatus] = []

    func record(_ status: InferenceRuntimeStatus) {
        lock.lock()
        recorded.append(status)
        lock.unlock()
    }

    func values() -> [InferenceRuntimeStatus] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}

func collectPipelineEvents(
    _ stream: AsyncThrowingStream<PipelineEvent, Error>
) async throws -> [PipelineEvent] {
    var events: [PipelineEvent] = []
    for try await event in stream {
        events.append(event)
    }
    return events
}

func collectStrings(
    _ stream: AsyncThrowingStream<String, Error>
) async throws -> [String] {
    var chunks: [String] = []
    for try await chunk in stream {
        chunks.append(chunk)
    }
    return chunks
}

func waitForCondition(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    condition: @escaping () async -> Bool
) async -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return await condition()
}
