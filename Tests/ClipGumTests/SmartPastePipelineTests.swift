import XCTest
@testable import ClipGum

final class SmartPastePipelineTests: XCTestCase {
    func testCleanMechanicalActionBypassesEngine() async throws {
        let engine = MockManagedInferenceEngine()
        let pipeline = SmartPastePipeline(engine: engine)
        let result = try pipeline.mechanicalResult(
            action: .clean,
            input: "https://example.com?utm_source=x&id=1"
        )
        XCTAssertEqual(result?.cleaned, "https://example.com?id=1")
        let calls = await engine.transformCalls
        XCTAssertTrue(calls.isEmpty)
    }

    func testURLAndSecretMechanicalActionsBypassEngine() async throws {
        let engine = MockManagedInferenceEngine()
        let pipeline = SmartPastePipeline(engine: engine)
        let url = try pipeline.mechanicalResult(
            action: .urlClean,
            input: "https://example.com?fbclid=x&id=1&token=Abcd1234efgh5678"
        )
        XCTAssertEqual(
            url?.cleaned,
            "https://example.com?id=1&token=Abcd1234efgh5678"
        )
        let scrub = try pipeline.mechanicalResult(
            action: .secretScrub,
            input: "token=Abcd1234efgh5678"
        )
        XCTAssertEqual(scrub?.cleaned, "token=\(RuleCleaningService.redactionPlaceholder)")
        let calls = await engine.transformCalls
        XCTAssertTrue(calls.isEmpty)
    }

    func testJSONFormattingIsSynchronousAndEngineFree() async throws {
        let engine = MockManagedInferenceEngine()
        let pipeline = SmartPastePipeline(engine: engine)
        let result = try pipeline.mechanicalResult(
            action: .formatJSON,
            input: #"{"b":2,"a":1}"#
        )
        XCTAssertEqual(result?.cleaned, "{\n  \"a\" : 1,\n  \"b\" : 2\n}")
        let calls = await engine.transformCalls
        XCTAssertTrue(calls.isEmpty)
    }

    func testInvalidJSONFailsBeforeEngine() async throws {
        let engine = MockManagedInferenceEngine()
        let pipeline = SmartPastePipeline(engine: engine)
        XCTAssertThrowsError(try pipeline.mechanicalResult(
            action: .formatJSON,
            input: "{not json}"
        )) { error in
            XCTAssertEqual(error as? JSONFormattingError, .invalidDocument)
        }
        let calls = await engine.transformCalls
        XCTAssertTrue(calls.isEmpty)
    }

    func testInferenceStreamsChunksThenValidatedCompletion() async throws {
        let engine = MockManagedInferenceEngine(chunks: ["This ", "is correct."])
        let pipeline = SmartPastePipeline(engine: engine)
        let stream = try await pipeline.inferenceStream(
            action: .correction,
            input: "This are correct.",
            maxTokens: 100
        )
        let events = try await collectPipelineEvents(stream)
        XCTAssertEqual(events.count, 3)
        guard case .completed(let result)? = events.last else {
            return XCTFail("Missing validated completion")
        }
        XCTAssertEqual(result.output, "This is correct.")
        XCTAssertEqual(result.streamedChunks, 2)
        XCTAssertTrue(result.validation.canExport)
    }

    func testEngineReceivesOnlyDeterministicallyCleanedInput() async throws {
        let engine = MockManagedInferenceEngine(chunks: [""])
        let pipeline = SmartPastePipeline(engine: engine)
        let original = "https://api.corp?id=42&utm_source=x&token=Abcd1234efgh5678 10.0.0.1"
        let expected = RuleCleaningService().clean(original).cleaned
        let stream = try await pipeline.inferenceStream(
            action: .correction,
            input: original,
            maxTokens: 100
        )
        _ = try await collectPipelineEvents(stream)
        let calls = await engine.transformCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.input, expected)
        XCTAssertFalse(calls.first?.input.contains("Abcd1234efgh5678") == true)
        XCTAssertFalse(calls.first?.input.contains("utm_source") == true)
        XCTAssertTrue(calls.first?.prompt.contains("CORRECTION ONLY") == true)
    }

    func testPipelineHardCapsRequestedTokens() async throws {
        let engine = MockManagedInferenceEngine(chunks: ["This is correct."])
        let pipeline = SmartPastePipeline(engine: engine)
        let stream = try await pipeline.inferenceStream(
            action: .correction,
            input: "This is correct.",
            maxTokens: 99_999
        )
        _ = try await collectPipelineEvents(stream)
        let calls = await engine.transformCalls
        XCTAssertEqual(calls.first?.maxTokens, 512)
    }

    func testValidationFailureCompletesButCannotExport() async throws {
        let engine = MockManagedInferenceEngine(chunks: ["Version 2 is stable."])
        let pipeline = SmartPastePipeline(engine: engine)
        let stream = try await pipeline.inferenceStream(
            action: .correction,
            input: "Version 1 is stable.",
            maxTokens: 100
        )
        let events = try await collectPipelineEvents(stream)
        guard case .completed(let result)? = events.last else {
            return XCTFail("Missing completion")
        }
        XCTAssertFalse(result.validation.canExport)
        XCTAssertTrue(result.validation.errors.contains { $0.code == .numbersChanged })
    }

    func testOutOfMemoryBeforeStreamThrowsTypedError() async throws {
        let engine = MockManagedInferenceEngine(
            transformError: InferenceEngineError.outOfMemory
        )
        let pipeline = SmartPastePipeline(engine: engine)
        do {
            _ = try await pipeline.inferenceStream(
                action: .rewrite,
                input: "A concise professional rewrite.",
                maxTokens: 100
            )
            XCTFail("Expected out-of-memory error")
        } catch {
            XCTAssertEqual(error as? InferenceEngineError, .outOfMemory)
        }
    }

    func testOutOfMemoryDuringStreamNeverEmitsCompletion() async throws {
        let engine = MockManagedInferenceEngine(
            chunks: ["partial"],
            streamError: InferenceEngineError.outOfMemory
        )
        let pipeline = SmartPastePipeline(engine: engine)
        let stream = try await pipeline.inferenceStream(
            action: .correction,
            input: "A source sentence.",
            maxTokens: 100
        )
        var events: [PipelineEvent] = []
        do {
            for try await event in stream {
                events.append(event)
            }
            XCTFail("Expected stream failure")
        } catch {
            XCTAssertEqual(error as? InferenceEngineError, .outOfMemory)
        }
        XCTAssertEqual(events, [.chunk("partial")])
    }

    func testRunawayOutputByteBudgetDiscardsCompletion() async throws {
        let engine = MockManagedInferenceEngine(chunks: [
            String(repeating: "a", count: 10_000),
            String(repeating: "b", count: 10_000)
        ])
        let pipeline = SmartPastePipeline(engine: engine)
        let stream = try await pipeline.inferenceStream(
            action: .correction,
            input: "short",
            maxTokens: 512
        )
        do {
            _ = try await collectPipelineEvents(stream)
            XCTFail("Expected output budget failure")
        } catch {
            XCTAssertEqual(error as? InferenceEngineError, .outputTooLarge)
        }
    }
}
