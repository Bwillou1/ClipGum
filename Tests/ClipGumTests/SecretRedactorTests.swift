import XCTest
@testable import ClipGum

final class SecretRedactorTests: XCTestCase {
    private let redactor = SecretRedactor(placeholder: RuleCleaningService.redactionPlaceholder)
    private let marker = RuleCleaningService.redactionPlaceholder

    func testRedactsAwsAccessKeysWhereverTheyAppear() {
        assertRedaction(
            "aws_access_key_id = \"AKIAIOSFODNN7EXAMPLE\"",
            "aws_access_key_id = \"\(marker)\"",
            count: 1
        )
        assertRedaction(
            "temporary=ASIAIOSFODNN7LXM22JI",
            "temporary=\(marker)",
            count: 1
        )
    }

    func testDoesNotPartiallyRedactInvalidAwsShapes() {
        for input in [
            "AKIBIOSFODNN7EXAMPLE",
            "AKIAIOSFODNN7EXAMPL",
            "AKIA0000000000000000",
            "XAKIAIOSFODNN7EXAMPLE"
        ] {
            assertRedaction(input, input, count: 0)
        }
    }

    func testRedactsNestedJsonTokenWithoutChangingStructure() {
        assertRedaction(
            #"{"outer":{"api_key":"abcdEFGH1234ijkl","safe":"value"},"password":"short"}"#,
            #"{"outer":{"api_key":"\#(marker)","safe":"value"},"password":"short"}"#,
            count: 1
        )
    }

    func testRedactsCommonGenericSecretAssignments() {
        let keys = [
            "api_key", "apiKey", "access_token", "accessToken",
            "client_secret", "clientSecret", "AWS_SECRET_ACCESS_KEY",
            "GITHUB_TOKEN", "password", "passwd", "credentials"
        ]

        for key in keys {
            assertRedaction(
                "\(key)=Abcd1234efgh5678",
                "\(key)=\(marker)",
                count: 1
            )
        }
    }

    func testRedactsBearerTokenAndPreservesHeader() {
        assertRedaction(
            "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.signature",
            "Authorization: Bearer \(marker)",
            count: 1
        )
    }

    func testRedactsCompleteBase64LikeValueIncludingPadding() {
        assertRedaction(
            "api_key=Abcd+1234/efgh==;",
            "api_key=\(marker);",
            count: 1
        )
    }

    func testShortOrNonSecretAssignmentsAreNotChanged() {
        for input in [
            "token=null", "token=short", "password=hunter2",
            "api_id=Abcd1234efgh5678", "monkey=Abcd1234efgh5678",
            "secretary=Abcd1234efgh5678", "public_key=Abcd1234efgh5678",
            "Authorization: Bearer short"
        ] {
            assertRedaction(input, input, count: 0)
        }
    }

    func testRedactsEveryRfc1918Range() {
        for address in [
            "10.0.0.1", "10.255.255.255", "172.16.0.1",
            "172.31.255.255", "192.168.1.20"
        ] {
            assertRedaction("ip=\(address)", "ip=\(marker)", count: 1)
        }
    }

    func testDoesNotRedactPublicLoopbackLinkLocalOrOutOfRangeAddresses() {
        for address in [
            "11.0.0.1", "172.15.0.1", "172.32.0.1", "192.167.1.1",
            "8.8.8.8", "127.0.0.1", "169.254.1.1",
            "999.10.0.1", "10.0.0.999"
        ] {
            assertRedaction(address, address, count: 0)
        }
    }

    func testDoesNotRedactAnIpInsideALongerDottedSequence() {
        for input in ["1.10.0.0.1", "10.0.0.1.5"] {
            assertRedaction(input, input, count: 0)
        }
    }

    func testRedactsIpInsideUrlButPreservesPortAndPath() {
        assertRedaction(
            "https://10.0.0.1:8080/health",
            "https://\(marker):8080/health",
            count: 1
        )
    }

    func testRedactsMultipleAddresses() {
        assertRedaction(
            "route 10.0.0.1 -> 192.168.1.2 via 8.8.8.8",
            "route \(marker) -> \(marker) via 8.8.8.8",
            count: 2
        )
    }

    func testRedactsDocumentedInternalHostnameSuffixes() {
        for host in [
            "api.internal", "db.corp", "printer.local", "service.lan",
            "foo.intranet", "api.intra", "host.home.arpa"
        ] {
            assertRedaction("host=\(host)", "host=\(marker)", count: 1)
        }
    }

    func testDoesNotPartiallyRedactPublicDomainsOrSingleLabels() {
        for host in [
            "api.internal.example.com", "api.corp.evil.com", "example.com",
            "localhost", "single-label"
        ] {
            assertRedaction(host, host, count: 0)
        }
    }

    func testRedactsInternalHostInUrlAndEmailOnlyAtHostname() {
        assertRedaction(
            "https://api.corp:8443/v1 admin@db.internal",
            "https://\(marker):8443/v1 admin@\(marker)",
            count: 2
        )
    }

    func testNestedTokensInArraysAndUrlsAreCompletelyRedacted() {
        let input = #"{"items":[{"token":"Abcd1234efgh5678"}],"url":"https://example.com?access_token=Zyxw9876vuts5432&id=1"}"#
        let expected = #"{"items":[{"token":"\#(marker)"}],"url":"https://example.com?access_token=\#(marker)&id=1"}"#
        assertRedaction(input, expected, count: 2)
    }

    func testDelimitersAroundNestedTokenArePreserved() {
        assertRedaction(
            "value=(token=Abcd1234efgh5678);",
            "value=(token=\(marker));",
            count: 1
        )
    }

    func testAwsValueInsideGenericAssignmentIsCountedOnce() {
        assertRedaction(
            "token=AKIAIOSFODNN7EXAMPLE",
            "token=\(marker)",
            count: 1
        )
    }

    func testTokenBoundariesAvoidPartialRedaction() {
        for input in [
            "token=Abcd1234efgh:remaining",
            "Authorization: Bearer Abcd1234efgh:remaining"
        ] {
            assertRedaction(input, input, count: 0)
        }

        assertRedaction(
            "token=Abcd1234efgh5678#fragment",
            "token=\(marker)#fragment",
            count: 1
        )
    }

    func testAlreadyRedactedTextIsIdempotent() {
        let input = "token=\"\(marker)\" Authorization: Bearer \(marker) host=\(marker)"
        assertRedaction(input, input, count: 0)
    }

    private func assertRedaction(
        _ input: String,
        _ expected: String,
        count: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = redactor.redactSecrets(in: input)
        XCTAssertEqual(result.output, expected, file: file, line: line)
        XCTAssertEqual(result.changeCount, count, file: file, line: line)
    }
}
