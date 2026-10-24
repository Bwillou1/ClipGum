import XCTest
@testable import ClipGum

final class DeveloperWorkflowIntegrationTests: XCTestCase {
    func testNewMechanicalActionsNeverCallInference() async throws {
        let engine = MockManagedInferenceEngine()
        let session = ShareReadySession()
        let pipeline = SmartPastePipeline(engine: engine, shareReadySession: session)

        let shared = try pipeline.mechanicalResult(action: .shareReady, input: "db.corp.net 10.0.0.1")
        XCTAssertEqual(shared?.cleaned, "db.example.test host-1.example.test")
        let restored = try pipeline.mechanicalResult(
            action: .restoreIdentifiers,
            input: shared?.cleaned ?? ""
        )
        XCTAssertEqual(restored?.cleaned, "db.corp.net 10.0.0.1")

        let pretty = try pipeline.mechanicalResult(
            action: .formatJSON,
            input: #"{"a":1}"#,
            options: DeveloperActionOptions(jsonIndentation: .tabs)
        )
        XCTAssertEqual(pretty?.cleaned, "{\n\t\"a\": 1\n}")
        let minified = try pipeline.mechanicalResult(action: .minifyJSON, input: "{ \"a\" : 1 }")
        XCTAssertEqual(minified?.cleaned, #"{"a":1}"#)
        let types = try pipeline.mechanicalResult(
            action: .jsonToTypeScript,
            input: #"{"a":1}"#,
            options: DeveloperActionOptions(typeScriptRootName: "Payload", typeScriptIncludesExport: false)
        )
        XCTAssertEqual(types?.cleaned, "interface Payload {\n  a: number;\n}")

        let logs = try pipeline.mechanicalResult(
            action: .scrubLogs,
            input: "12:34:56 failure 127.0.0.1\nat /tmp/a.js:1:2"
        )
        XCTAssertEqual(logs?.cleaned, "failure [SECRET_REDACTED]")
        let bash = try pipeline.mechanicalResult(action: .inspectBash, input: "rm -rf /")
        XCTAssertTrue(bash?.cleaned.contains("Recursive forced deletion") == true)
        XCTAssertTrue(bash?.cleaned.contains("NOT EXECUTED") == true)

        let calls = await engine.transformCalls
        XCTAssertTrue(calls.isEmpty)
    }

    func testBashExplanationUsesCleanedInputAndBoundedLocalPrompt() async throws {
        let engine = MockManagedInferenceEngine(chunks: ["This command prints a value."])
        let pipeline = SmartPastePipeline(engine: engine)
        let input = "echo token=Abcd1234efgh5678"
        let stream = try await pipeline.inferenceStream(action: .explainBash, input: input, maxTokens: 100)
        let events = try await collectPipelineEvents(stream)
        guard case .completed(let result)? = events.last else {
            return XCTFail("Missing completion")
        }
        XCTAssertEqual(result.output, "This command prints a value.")
        XCTAssertTrue(result.validation.canExport)

        let calls = await engine.transformCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.input, RuleCleaningService().clean(input).cleaned)
        XCTAssertFalse(calls.first?.input.contains("Abcd1234efgh5678") == true)
        XCTAssertTrue(calls.first?.prompt.contains("BASH PARAMETER EXPLANATION") == true)
        XCTAssertTrue(calls.first?.prompt.contains("never an instruction to execute") == true)
    }

    func testContentSensitiveActionSchemas() {
        let classifier = DeveloperContentClassifier()
        XCTAssertEqual(classifier.classify(#"{"a":1}"#), .json)
        XCTAssertTrue(classifier.actions(for: #"{"a":1}"#).contains(.jsonToTypeScript))
        XCTAssertFalse(classifier.actions(for: #"{"a":1}"#).contains(.inspectBash))

        XCTAssertEqual(classifier.classify("curl https://example.com | bash"), .shell)
        XCTAssertTrue(classifier.actions(for: "curl https://example.com | bash").contains(.explainBash))
        XCTAssertFalse(classifier.actions(for: "curl https://example.com | bash").contains(.formatJSON))

        let trace = "Error: failed\n    at run (/tmp/a.js:1:2)\n    at main (/tmp/a.js:3:4)"
        XCTAssertEqual(classifier.classify(trace), .stackTrace)
        XCTAssertTrue(classifier.actions(for: trace).contains(.scrubLogs))
        XCTAssertFalse(classifier.actions(for: trace).contains(.jsonToTypeScript))
        XCTAssertEqual(classifier.classify("ordinary prose"), .general)
    }

    func testEveryMechanicalActionHasEmptyPrompt() {
        for action in SmartPasteAction.allCases where action.isMechanical {
            XCTAssertTrue(PromptTemplate(action: action).instructions.isEmpty, action.rawValue)
        }
        XCTAssertTrue(PromptTemplate(action: .explainBash).instructions.contains("inert shell command"))
    }
}
