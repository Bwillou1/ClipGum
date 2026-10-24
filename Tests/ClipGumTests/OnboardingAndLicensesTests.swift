import Foundation
import XCTest
@testable import ClipGum

@MainActor
final class OnboardingAndLicensesTests: XCTestCase {
    func testFirstRunWalkthroughStartsIncompleteAndFinishesExplicitly() {
        let suite = "ClipGumTests.Onboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = OnboardingController(defaults: defaults)
        XCTAssertFalse(controller.isCompleted)
        XCTAssertEqual(controller.step, .explicitTrigger)
        controller.advance()
        XCTAssertEqual(controller.step, .permissions)
        controller.advance()
        XCTAssertTrue(controller.isLastStep)
        controller.goBack()
        XCTAssertEqual(controller.step, .permissions)
        controller.advance()
        let finished = expectation(description: "onboarding closed")
        controller.onFinish = { finished.fulfill() }
        controller.finish()
        wait(for: [finished], timeout: 1)
        XCTAssertTrue(controller.isCompleted)
        XCTAssertTrue(defaults.bool(forKey: "phase5.onboarding.completed"))
    }

    func testPermissionRecoveryDoesNotConflateCopyAndPaste() {
        let denied = PermissionRecoveryGuide.accessibility(isTrusted: false)
        XCTAssertFalse(denied.canPaste)
        XCTAssertTrue(denied.recoverySteps.joined(separator: " ").contains("Copy Result"))
        let granted = PermissionRecoveryGuide.accessibility(isTrusted: true)
        XCTAssertTrue(granted.canPaste)
        XCTAssertEqual(granted.recoverySteps.count, 1)
    }

    func testEveryLicenseAndCreditResourceIsEmbedded() {
        XCTAssertGreaterThanOrEqual(LicenseCatalog.entries.count, 12)
        for entry in LicenseCatalog.entries {
            let text = entry.loadText()
            XCTAssertFalse(text.isEmpty, entry.id)
            XCTAssertFalse(text.contains("distribution package is incomplete"), entry.id)
        }
    }

    func testSBOMContainsPinsAndMarksPrismMLAsUnbundled() throws {
        let entry = try XCTUnwrap(LicenseCatalog.entries.first { $0.id == "sbom" })
        let object = try JSONSerialization.jsonObject(with: Data(entry.loadText().utf8)) as? [String: Any]
        let bom = try XCTUnwrap(object)
        XCTAssertEqual(bom["bomFormat"] as? String, "CycloneDX")
        let components = try XCTUnwrap(bom["components"] as? [[String: Any]])
        XCTAssertTrue(components.contains { $0["name"] as? String == "Sparkle" && $0["version"] as? String == "2.10.0" })
        let prism = try XCTUnwrap(components.first { $0["name"] as? String == "PrismML Ternary Bonsai" })
        XCTAssertEqual(prism["scope"] as? String, "optional")
        let properties = try XCTUnwrap(prism["properties"] as? [[String: String]])
        XCTAssertTrue(properties.contains { $0["name"] == "clipgum:bundled" && $0["value"] == "false" })
    }
}
