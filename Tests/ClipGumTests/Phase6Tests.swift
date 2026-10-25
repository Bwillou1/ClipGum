import AppKit
import ClipGumCore
import XCTest
@testable import ClipGum

final class Phase6CoreTests: XCTestCase {
    func testDeterministicSanitizerIsOfflineAndIdempotent() {
        let input = "https://example.com/?utm_source=x&id=1 token=Abcd1234efgh5678 8.8.8.8"
        let result = DeterministicTransforms.sanitize(input)
        XCTAssertEqual(result.output, "https://example.com/?id=1 token=[REDACTED] [REDACTED]")
        XCTAssertEqual(DeterministicTransforms.sanitize(result.output).output, result.output)
    }

    func testJSONToTypeScriptAndTableAreDeterministic() throws {
        let type = try DeterministicTransforms.jsonToTypeScript(#"{"name":"a","count":2,"items":[true,false]}"#)
        XCTAssertTrue(type.contains("export type Root"))
        XCTAssertTrue(type.contains("count: number"))
        XCTAssertTrue(type.contains("items: boolean[]"))
        XCTAssertEqual(try DeterministicTransforms.extractTable("a,b\r\n1,\"x,y\"\r\n"), "a,b\n1,\"x,y\"")
    }

    func testBoopScriptRunsWithoutHostBridges() throws {
        let output = try JavaScriptPluginEngine().evaluate(
            script: "function main(input) { return input.trim().toUpperCase(); }",
            input: "  local only  "
        )
        XCTAssertEqual(output, "LOCAL ONLY")
    }

    func testScriptRejectsNetworkAndFilesystemNames() {
        XCTAssertThrowsError(try JavaScriptPluginEngine().evaluate(
            script: "function main(input) { return fetch('https://example.com'); }",
            input: "safe"
        )) { error in
            guard let ruleError = error as? CustomRuleError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue([.scriptFailed, .nonStringResult].contains(ruleError))
        }
        XCTAssertThrowsError(try JavaScriptPluginEngine().evaluate(
            script: "function main(input) { return readFile('/etc/passwd'); }",
            input: "safe"
        ))
    }

    func testInfiniteLoopIsTerminatedWithinBudget() {
        let started = DispatchTime.now().uptimeNanoseconds
        XCTAssertThrowsError(try JavaScriptPluginEngine().evaluate(
            script: "function main(input) { while (true) {} }",
            input: "safe"
        )) { error in
            XCTAssertEqual(error as? CustomRuleError, .executionTimedOut)
        }
        let elapsedMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        XCTAssertLessThan(elapsedMilliseconds, 2_000, "A runaway script must not hang the host test")
    }

    func testRulePackChecksumDetectsTampering() throws {
        let rule = CustomRule(name: "Trim", kind: .script, source: "function main(input) { return input.trim(); }")
        let data = try RulePackCodec.encode(rules: [rule])
        XCTAssertEqual(try RulePackCodec.decode(data), [rule])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["checksum"] = String(repeating: "0", count: 64)
        let changed = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try RulePackCodec.decode(changed)) { error in
            XCTAssertEqual(error as? CustomRuleError, .checksumMismatch)
        }
    }

    func testRegexRulesDoNotRequireJavaScript() throws {
        let rule = CustomRule(name: "Mask", kind: .regex, source: "secret", replacement: "[x]")
        XCTAssertEqual(try CustomRuleEngine().apply("a secret", rules: [rule], allowScripts: false), "a [x]")
        let script = CustomRule(name: "Script", kind: .script, source: "function main(input) { return input; }")
        XCTAssertThrowsError(try CustomRuleEngine().apply("x", rules: [script], allowScripts: false)) {
            XCTAssertEqual($0 as? CustomRuleError, .scriptDisabledByPolicy)
        }
    }

    func testLargeCLIStyleInputStaysBoundedAndLossless() throws {
        let line = "token=Abcd1234efgh5678 https://example.com/?utm_source=x&id=1\n"
        var input = ""
        while input.utf8.count < 10 * 1_024 * 1_024 { input += line }
        let result = DeterministicTransforms.sanitize(input)
        XCTAssertFalse(result.output.contains("Abcd1234efgh5678"))
        XCTAssertFalse(result.output.contains("utm_source"))
        XCTAssertEqual(result.output.split(separator: "\n", omittingEmptySubsequences: false).count,
                       input.split(separator: "\n", omittingEmptySubsequences: false).count)
    }

    func testManagedPolicyReadsForcedValuesWithoutWriting() throws {
        let suite = "ClipGumPhase6Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: ManagedPolicyKey.forceSecretRedaction.rawValue)
        defaults.set(true, forKey: ManagedPolicyKey.disableCustomScripts.rawValue)
        let store = UserDefaultsPolicyStore(
            defaults: defaults,
            forcedKeys: [ManagedPolicyKey.forceSecretRedaction.rawValue]
        )
        let policy = PolicyCenter(store: store).snapshot()
        XCTAssertTrue(policy.forceSecretRedaction)
        XCTAssertTrue(policy.isForced(.forceSecretRedaction))
        XCTAssertTrue(policy.disableCustomScripts)
        XCTAssertFalse(policy.isForced(.disableCustomScripts))
        XCTAssertEqual(policy.lockedLabels, ["Secret redaction enforced"])
    }

    func testThermalBudgetCapsGenerationAndCompactorCancels() async {
        XCTAssertEqual(ThermalBudget.maximumTokens(requested: 512, thermalState: .nominal), 512)
        XCTAssertEqual(ThermalBudget.maximumTokens(requested: 512, thermalState: .serious), 128)
        XCTAssertTrue(ThermalBudget.requiresDeterministicFallback(thermalState: .critical))
        let compactor = MemoryCompactor()
        let ran = expectation(description: "cancelled compactor must not run")
        ran.isInverted = true
        compactor.schedule(after: 0.1) { ran.fulfill() }
        compactor.cancel()
        await fulfillment(of: [ran], timeout: 0.3)
        XCTAssertFalse(compactor.isScheduled)
    }
}

@MainActor
final class Phase6AppBoundaryTests: XCTestCase {
    func testManagedRedactionIsAppliedAtFinalPasteboardWrite() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipGumPhase6.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let service = PasteService(
            pasteboard: SystemPasteboard(pasteboard: pasteboard),
            requiresSecretRedaction: { true }
        )
        try? service.copyResult("token=Abcd1234efgh5678")
        XCTAssertEqual(pasteboard.string(forType: .string), "token=[REDACTED]")

        let payload = PasteboardPayload(plainText: "8.8.8.8", html: "<b>8.8.8.8</b>", rtfData: Data("{\\rtf1 8.8.8.8}".utf8))
        try? service.copyResult(payload)
        XCTAssertEqual(pasteboard.string(forType: .string), "[REDACTED]")
        XCTAssertNil(pasteboard.string(forType: .html))
        pasteboard.clearContents()
    }

    func testTelemetryLockCannotBeOverridden() {
        let suite = "ClipGumPhase6Diagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let diagnostics = DiagnosticsEngine(defaults: defaults, telemetryLocked: true)
        diagnostics.setEnabled(true)
        XCTAssertFalse(diagnostics.isEnabled)
        diagnostics.applyPolicy(lockTelemetry: false)
        diagnostics.setEnabled(true)
        XCTAssertTrue(diagnostics.isEnabled)
        diagnostics.applyPolicy(lockTelemetry: true)
        XCTAssertFalse(diagnostics.isEnabled)
    }

    func testDeepLinksNeverContainContent() {
        XCTAssertEqual(ClipGumDeepLink.destination(for: URL(string: "clipgum://rules")!), .rules)
        XCTAssertNil(ClipGumDeepLink.destination(for: URL(string: "https://rules")!))
    }
}
