import XCTest
@testable import ClipGum

final class RuleCleaningServiceTests: XCTestCase {
    private let service = RuleCleaningService()
    private let marker = RuleCleaningService.redactionPlaceholder

    func testPipelineCombinesUrlCleaningAndSecretRedaction() {
        let input = "Visit https://example.com/path?utm_source=x&id=42&access_token=Abcd1234efgh5678 at 10.0.0.1"
        let expected = "Visit https://example.com/path?id=42&access_token=\(marker) at \(marker)"

        let result = service.clean(input)

        XCTAssertEqual(result.original, input)
        XCTAssertEqual(result.cleaned, expected)
        XCTAssertEqual(result.removedTrackingParameters, 1)
        XCTAssertEqual(result.redactedSecrets, 2)
        XCTAssertTrue(result.hasChanges)
    }

    func testRepeatedCallsAndSeparateInstancesHaveNoState() {
        let input = #"{"token":"Abcd1234efgh5678","url":"https://example.com?fbclid=x&id=1"}"#
        let first = service.clean(input)
        let second = service.clean(input)
        let third = RuleCleaningService().clean(input)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first, third)
        XCTAssertEqual(first.redactedSecrets, 1)
        XCTAssertEqual(first.removedTrackingParameters, 1)
    }

    func testFullPipelineIsIdempotent() {
        let input = "https://api.corp/path?utm_source=x&api_key=Abcd1234efgh5678 192.168.1.1"
        let once = service.clean(input)
        let twice = service.clean(once.cleaned)

        XCTAssertEqual(twice.cleaned, once.cleaned)
        XCTAssertEqual(twice.removedTrackingParameters, 0)
        XCTAssertEqual(twice.redactedSecrets, 0)
    }

    func testNoMatchingRulesReturnsByteIdenticalUnicode() {
        let input = "Hello 👋 — café\nhttps://example.com/?q=hello+world&id=1"
        let result = service.clean(input)

        XCTAssertEqual(result.cleaned, input)
        XCTAssertFalse(result.hasChanges)
        XCTAssertEqual(result.removedTrackingParameters, 0)
        XCTAssertEqual(result.redactedSecrets, 0)
    }

    func testIndividualTransformsRemainAvailableAndPure() {
        XCTAssertEqual(
            service.stripURLTracking(from: "https://example.com?utm_source=x&id=1"),
            "https://example.com?id=1"
        )
        XCTAssertEqual(service.redactSecrets(from: "ip=10.0.0.1"), "ip=\(marker)")
    }

    func testSecretInsideRemovedTrackerDoesNotCauseExtraRedactionCount() {
        let result = service.clean("https://example.com?utm_source=AKIAIOSFODNN7EXAMPLE&id=1")

        XCTAssertEqual(result.cleaned, "https://example.com?id=1")
        XCTAssertEqual(result.removedTrackingParameters, 1)
        XCTAssertEqual(result.redactedSecrets, 0)
    }
}
