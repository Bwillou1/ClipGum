import Foundation
import XCTest
@testable import ClipGum

@MainActor
final class DiagnosticsEngineTests: XCTestCase {
    private func decodePayload(_ data: Data) throws -> DiagnosticPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DiagnosticPayload.self, from: data)
    }

    private func makeEngine(
        memory: @escaping () -> UInt64? = { 100 }
    ) -> (DiagnosticsEngine, UserDefaults, String) {
        let suite = "ClipGumTests.Diagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let engine = DiagnosticsEngine(
            defaults: defaults,
            memoryProvider: memory,
            clock: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        return (engine, defaults, suite)
    }

    func testDiagnosticsAreOffByDefaultAndRecordNothing() throws {
        let (engine, _, suite) = makeEngine()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        XCTAssertFalse(engine.isEnabled)
        engine.record(feature: .cleanedLink, latencyNanoseconds: 5_000_000)
        XCTAssertTrue(engine.snapshot.features.isEmpty)
        let payload = try decodePayload(engine.payloadData())
        XCTAssertTrue(payload.features.isEmpty)
        XCTAssertEqual(payload.peakResidentMemoryBytes, 0)
    }

    func testOptInComputesNearestRankPercentilesAndPeakRAM() throws {
        var memory: UInt64 = 100
        let (engine, _, suite) = makeEngine(memory: { memory })
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        engine.setEnabled(true)
        for index in UInt64(1)...10 {
            memory = index * 10
            engine.record(feature: .tableToCSV, latencyNanoseconds: index * 1_000_000)
        }
        let payload = try decodePayload(engine.payloadData())
        let feature = try XCTUnwrap(payload.features.first)
        XCTAssertEqual(feature.activationCount, 10)
        XCTAssertEqual(feature.p50LatencyMilliseconds, 5)
        XCTAssertEqual(feature.p95LatencyMilliseconds, 10)
        XCTAssertEqual(payload.peakResidentMemoryBytes, 100)
    }

    func testLatencyStorageIsBoundedButActivationCountIsNotTruncated() {
        let (engine, _, suite) = makeEngine()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        engine.setEnabled(true)
        for index in UInt64(1)...300 {
            engine.record(feature: .deterministicClean, latencyNanoseconds: index * 1_000_000)
        }
        let metrics = engine.snapshot.features[.deterministicClean]
        XCTAssertEqual(metrics?.activationCount, 300)
        XCTAssertEqual(metrics?.latencySamples.count, 256)
        XCTAssertEqual(metrics?.latencySamples.first, 45)
        XCTAssertEqual(metrics?.latencySamples.last, 300)
    }

    func testOnlyFixedErrorCodesAreCounted() throws {
        let (engine, _, suite) = makeEngine()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        engine.setEnabled(true)
        engine.record(feature: .localRewrite, latencyNanoseconds: 1, error: .modelOutOfMemory)
        engine.record(feature: .localRewrite, latencyNanoseconds: 1, error: .modelOutOfMemory)
        let text = try engine.payloadText()
        XCTAssertTrue(text.contains("model_out_of_memory"))
        XCTAssertTrue(text.contains("\"count\" : 2"))
        XCTAssertFalse(text.contains("localizedDescription"))
    }

    func testPayloadContainsNoClipboardOutputTokenOrMappingFields() throws {
        let (engine, _, suite) = makeEngine()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        engine.setEnabled(true)
        engine.record(feature: .shareReady, latencyNanoseconds: 42)
        let text = try engine.payloadText()
        for forbidden in ["clipboard", "transformed", "regexToken", "sessionMapping", "prompt", "output"] {
            XCTAssertFalse(text.contains(forbidden), forbidden)
        }
        XCTAssertNoThrow(try DiagnosticPayloadSchema.validate(Data(text.utf8)))
    }

    func testClearAllDataResetsEveryValueAndWithdrawsOptIn() throws {
        let (engine, defaults, suite) = makeEngine()
        defer { defaults.removePersistentDomain(forName: suite) }
        engine.setEnabled(true)
        engine.record(feature: .richTextSanitized, latencyNanoseconds: 1, error: .invalidInput)
        engine.clearAllData()
        XCTAssertFalse(engine.isEnabled)
        XCTAssertNil(defaults.object(forKey: "phase5.diagnostics.enabled"))
        XCTAssertTrue(engine.snapshot.features.isEmpty)
        XCTAssertTrue(engine.snapshot.errors.isEmpty)
        XCTAssertEqual(engine.snapshot.peakResidentMemoryBytes, 0)
        let payload = try decodePayload(engine.payloadData())
        XCTAssertTrue(payload.features.isEmpty)
    }

    func testDisablingAlsoClearsPriorData() {
        let (engine, _, suite) = makeEngine()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        engine.setEnabled(true)
        engine.record(feature: .jsonFormatted, latencyNanoseconds: 1)
        engine.setEnabled(false)
        XCTAssertTrue(engine.snapshot.features.isEmpty)
        engine.record(feature: .jsonFormatted, latencyNanoseconds: 1)
        XCTAssertTrue(engine.snapshot.features.isEmpty)
    }

    func testIndependentSchemaRejectsInjectedContentAndUnknownEnums() throws {
        let (engine, _, suite) = makeEngine()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let valid = try engine.payloadData()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        object["clipboard"] = "raw secret"
        XCTAssertThrowsError(try DiagnosticPayloadSchema.validate(JSONSerialization.data(withJSONObject: object)))

        object.removeValue(forKey: "clipboard")
        object["features"] = [[
            "feature": "free_form_event",
            "activationCount": 1,
            "p50LatencyMilliseconds": 0,
            "p95LatencyMilliseconds": 0
        ]]
        XCTAssertThrowsError(try DiagnosticPayloadSchema.validate(JSONSerialization.data(withJSONObject: object)))
    }

    func testEveryPasteActionHasAClosedDiagnosticFeature() {
        for action in SmartPasteAction.allCases {
            XCTAssertNotNil(DiagnosticFeature(action: action), action.rawValue)
        }
    }
}
