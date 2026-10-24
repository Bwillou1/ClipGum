import XCTest
@testable import ClipGum

final class LocalInferenceEngineTests: XCTestCase {
    func testBackendSelectionAndModelSwitchUnloadOldBackend() async throws {
        let mlx = MockManagedInferenceEngine()
        let gguf = MockManagedInferenceEngine()
        let engine = LocalInferenceEngine(
            configuration: InferenceConfiguration(),
            mlxFactory: { _ in mlx },
            ggufFactory: { _ in gguf }
        )
        try await engine.loadModel(identifier: "mlx:/tmp/mlx-model")
        try await engine.loadModel(identifier: "gguf:/tmp/model.gguf")

        let mlxLoads = await mlx.loadIdentifiers
        let ggufLoads = await gguf.loadIdentifiers
        let mlxUnloads = await mlx.unloadCallCount
        XCTAssertEqual(mlxLoads, ["mlx:/tmp/mlx-model"])
        XCTAssertEqual(ggufLoads, ["gguf:/tmp/model.gguf"])
        XCTAssertEqual(mlxUnloads, 1)
    }

    func testSameModelLoadIsIdempotent() async throws {
        let backend = MockManagedInferenceEngine()
        let engine = LocalInferenceEngine(
            configuration: InferenceConfiguration(),
            mlxFactory: { _ in backend },
            ggufFactory: { _ in backend }
        )
        try await engine.loadModel(identifier: "mlx:/tmp/model")
        try await engine.loadModel(identifier: "mlx:/tmp/model")
        let loads = await backend.loadIdentifiers
        XCTAssertEqual(loads.count, 1)
    }

    func testInvalidIdentifierFailsBeforeBackendLoad() async throws {
        let backend = MockManagedInferenceEngine()
        let engine = LocalInferenceEngine(
            configuration: InferenceConfiguration(),
            mlxFactory: { _ in backend },
            ggufFactory: { _ in backend }
        )
        do {
            try await engine.loadModel(identifier: "https://example.com/model")
            XCTFail("Expected invalid identifier")
        } catch {
            XCTAssertEqual(error as? InferenceEngineError, .invalidIdentifier)
        }
        let loads = await backend.loadIdentifiers
        XCTAssertTrue(loads.isEmpty)
    }

    func testTransformRequiresLoadedModel() async throws {
        let engine = LocalInferenceEngine(
            configuration: InferenceConfiguration(),
            mlxFactory: { _ in MockManagedInferenceEngine() },
            ggufFactory: { _ in MockManagedInferenceEngine() }
        )
        do {
            _ = try await engine.transform(prompt: "p", input: "i", maxTokens: 10)
            XCTFail("Expected model-not-loaded error")
        } catch {
            XCTAssertEqual(error as? InferenceEngineError, .modelNotLoaded)
        }
    }

    func testTransformClampsTokensAndStreams() async throws {
        let backend = MockManagedInferenceEngine(chunks: ["a", "b"])
        let engine = LocalInferenceEngine(
            configuration: InferenceConfiguration(maximumOutputTokens: 128),
            mlxFactory: { _ in backend },
            ggufFactory: { _ in backend }
        )
        try await engine.loadModel(identifier: "mlx:/tmp/model")
        let stream = try await engine.transform(prompt: "p", input: "i", maxTokens: 999)
        let chunks = try await collectStrings(stream)
        let calls = await backend.transformCalls
        XCTAssertEqual(chunks, ["a", "b"])
        XCTAssertEqual(calls.first?.maxTokens, 128)
    }

    func testIdleTimeoutUnloadsModel() async throws {
        let backend = MockManagedInferenceEngine()
        let recorder = InferenceStatusRecorder()
        let engine = LocalInferenceEngine(
            configuration: InferenceConfiguration(idleUnloadTimeout: 0.05),
            mlxFactory: { _ in backend },
            ggufFactory: { _ in backend }
        )
        await engine.setStatusHandler { recorder.record($0) }
        try await engine.loadModel(identifier: "mlx:/tmp/model")

        let unloaded = await waitForCondition {
            let count = await backend.unloadCallCount
            return count == 1 && recorder.values().last == .idle
        }
        XCTAssertTrue(unloaded)
        XCTAssertEqual(recorder.values().last, .idle)
        XCTAssertTrue(recorder.values().contains { status in
            if case .ready(.mlx, _) = status {
                return true
            }
            return false
        })
    }

    func testOutOfMemoryBeforeStreamUnloadsModel() async throws {
        let backend = MockManagedInferenceEngine(
            transformError: InferenceEngineError.outOfMemory
        )
        let engine = LocalInferenceEngine(
            configuration: InferenceConfiguration(),
            mlxFactory: { _ in backend },
            ggufFactory: { _ in backend }
        )
        try await engine.loadModel(identifier: "mlx:/tmp/model")
        do {
            _ = try await engine.transform(prompt: "p", input: "i", maxTokens: 10)
            XCTFail("Expected out-of-memory error")
        } catch {
            XCTAssertEqual(error as? InferenceEngineError, .outOfMemory)
        }
        let unloads = await backend.unloadCallCount
        XCTAssertEqual(unloads, 1)
    }

    func testOutOfMemoryDuringStreamUnloadsModel() async throws {
        let backend = MockManagedInferenceEngine(
            chunks: ["partial"],
            streamError: InferenceEngineError.outOfMemory
        )
        let recorder = InferenceStatusRecorder()
        let engine = LocalInferenceEngine(
            configuration: InferenceConfiguration(),
            mlxFactory: { _ in backend },
            ggufFactory: { _ in backend }
        )
        await engine.setStatusHandler { recorder.record($0) }
        try await engine.loadModel(identifier: "mlx:/tmp/model")
        let stream = try await engine.transform(prompt: "p", input: "i", maxTokens: 10)
        do {
            _ = try await collectStrings(stream)
            XCTFail("Expected out-of-memory error")
        } catch {
            XCTAssertEqual(error as? InferenceEngineError, .outOfMemory)
        }
        let unloaded = await waitForCondition {
            let count = await backend.unloadCallCount
            let hasFailure = recorder.values().contains { status in
                if case .failed = status {
                    return true
                }
                return false
            }
            return count == 1 && hasFailure
        }
        XCTAssertTrue(unloaded)
        XCTAssertTrue(recorder.values().contains { status in
            if case .failed = status {
                return true
            }
            return false
        })
    }

    func testModelCannotUnloadWhileGenerationIsActive() async throws {
        let backend = MockManagedInferenceEngine(
            chunks: ["done"],
            streamDelayNanoseconds: 200_000_000
        )
        let engine = LocalInferenceEngine(
            configuration: InferenceConfiguration(),
            mlxFactory: { _ in backend },
            ggufFactory: { _ in backend }
        )
        try await engine.loadModel(identifier: "mlx:/tmp/model")
        let stream = try await engine.transform(prompt: "p", input: "i", maxTokens: 10)
        do {
            try await engine.unloadModel()
            XCTFail("Expected busy error")
        } catch {
            XCTAssertEqual(error as? InferenceEngineError, .engineBusy)
        }
        XCTAssertEqual(try await collectStrings(stream), ["done"])
    }

    func testFailedModelLoadClassifiesAndCleansUp() async throws {
        let backend = MockManagedInferenceEngine(
            loadError: InferenceEngineError.outOfMemory
        )
        let recorder = InferenceStatusRecorder()
        let engine = LocalInferenceEngine(
            configuration: InferenceConfiguration(),
            mlxFactory: { _ in backend },
            ggufFactory: { _ in backend }
        )
        await engine.setStatusHandler { recorder.record($0) }
        do {
            try await engine.loadModel(identifier: "mlx:/tmp/model")
            XCTFail("Expected load failure")
        } catch {
            XCTAssertEqual(error as? InferenceEngineError, .outOfMemory)
        }
        let unloads = await backend.unloadCallCount
        XCTAssertEqual(unloads, 1)
        XCTAssertTrue(recorder.values().contains { status in
            if case .failed = status {
                return true
            }
            return false
        })
    }

    func testConfigurationUpdateReachesIdleBackend() async throws {
        let backend = MockManagedInferenceEngine()
        let engine = LocalInferenceEngine(
            configuration: InferenceConfiguration(),
            mlxFactory: { _ in backend },
            ggufFactory: { _ in backend }
        )
        try await engine.loadModel(identifier: "mlx:/tmp/model")
        let updated = InferenceConfiguration(temperature: 0.3, maximumOutputTokens: 64)
        await engine.updateConfiguration(updated)
        let updates = await backend.configurationUpdates
        XCTAssertEqual(updates.last, updated)
    }
}
