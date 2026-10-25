import XCTest
@testable import ClipGum

final class URLTrackingCleanerTests: XCTestCase {
    private let cleaner = URLTrackingCleaner()

    func testRemovesRequiredTrackingParameters() {
        assertClean(
            "https://example.com/article?utm_source=newsletter&utm_medium=email&fbclid=abc&gclid=xyz",
            "https://example.com/article",
            removed: 4
        )
    }

    func testPreservesFunctionalParametersAndTheirOrder() {
        assertClean(
            "https://example.com/search?id=42&q=swift&utm_source=x&sort=asc&fbclid=abc",
            "https://example.com/search?id=42&q=swift&sort=asc",
            removed: 2
        )
    }

    func testPreservesDuplicateParametersAndExactPercentEscapes() {
        assertClean(
            "https://example.com/?id=1&id=2&utm_source=x&tag=a%2Fb&tag=a%2fb",
            "https://example.com/?id=1&id=2&tag=a%2Fb&tag=a%2fb",
            removed: 1
        )
    }

    func testDoesNotRoundTripAUrlWithoutTrackers() {
        let input = "https://example.com/a%2fb?q=hello+world&token=keep&si=keep&ref=keep"
        assertClean(input, input, removed: 0)
    }

    func testPreservesPathParameters() {
        assertClean(
            "https://example.com/session;jsessionid=ABC123/path;v=2?utm_source=x&download=1",
            "https://example.com/session;jsessionid=ABC123/path;v=2?download=1",
            removed: 1
        )
    }

    func testPreservesFragmentExactly() {
        assertClean(
            "https://example.com/page?utm_source=x&id=7#section?utm_medium=keep",
            "https://example.com/page?id=7#section?utm_medium=keep",
            removed: 1
        )
    }

    func testDropsEmptyQueryAfterRemovingOnlyTrackerButKeepsFragment() {
        assertClean(
            "https://example.com/page?fbclid=abc#install",
            "https://example.com/page#install",
            removed: 1
        )
    }

    func testMatchingIsCaseInsensitiveButUnknownPrefixIsKept() {
        assertClean(
            "HTTPS://EXAMPLE.COM/?UTM_SOURCE=x&FbClId=y&GCLID=z&utm_custom=a&utmx=b&ID=1",
            "HTTPS://EXAMPLE.COM/?utmx=b&ID=1",
            removed: 4
        )
    }

    func testDecodesOnlyParameterNamesForMatching() {
        assertClean(
            "https://example.com/?%75tm_source=x&utm%5Fmedium=y&id=a%2Fb",
            "https://example.com/?id=a%2Fb",
            removed: 2
        )
    }

    func testPreservesUserInfoPortAndEncodedValue() {
        assertClean(
            "https://user:pass@example.com:8443/a?utm_source=x&keep=a%2Bb",
            "https://user:pass@example.com:8443/a?keep=a%2Bb",
            removed: 1
        )
    }

    func testSupportsFlagParameters() {
        assertClean(
            "https://example.com/?utm_source&debug&fbclid",
            "https://example.com/?debug",
            removed: 2
        )
    }

    func testPreservesEmptyQuerySegmentsAroundFunctionalParameters() {
        assertClean(
            "https://example.com/?id=1&&utm_source=x&tag=2",
            "https://example.com/?id=1&&tag=2",
            removed: 1
        )
    }

    func testHandlesSeveralUrlsInProseAndKeepsSentencePunctuation() {
        assertClean(
            "See (https://example.com/a?utm_source=x&id=2), then https://example.org/?fbclid=abc.",
            "See (https://example.com/a?id=2), then https://example.org/.",
            removed: 2
        )
    }

    func testKeepsBalancedUrlParentheses() {
        assertClean(
            "https://en.wikipedia.org/wiki/A_(test)?utm_source=x",
            "https://en.wikipedia.org/wiki/A_(test)",
            removed: 1
        )
    }

    func testHandlesAngleBracketWrappedUrl() {
        assertClean(
            "<https://example.com/?utm_source=x&id=1>",
            "<https://example.com/?id=1>",
            removed: 1
        )
    }

    func testHandlesUnicodeBeforeAndInsideUrl() {
        assertClean(
            "before 👋 https://example.com/café?utm_source=x&name=Jalapeño after",
            "before 👋 https://example.com/café?name=Jalapeño after",
            removed: 1
        )
    }

    func testTrackerInPathIsNotAQueryParameter() {
        assertClean(
            "https://example.com/utm_source=x?utm_source=y",
            "https://example.com/utm_source=x",
            removed: 1
        )
    }

    func testQueryLikeTextInsideFragmentIsUntouched() {
        let input = "https://example.com/#section?utm_source=x"
        assertClean(input, input, removed: 0)
    }

    func testEmptyQueryIsByteIdentical() {
        let input = "https://example.com/?"
        assertClean(input, input, removed: 0)
    }

    func testMalformedPercentEscapeLeavesWholeUrlUntouched() {
        let input = "https://example.com/?utm_source=x&bad=%zz"
        assertClean(input, input, removed: 0)
    }

    func testMissingHostLeavesUrlUntouched() {
        let input = "https://?utm_source=x"
        assertClean(input, input, removed: 0)
    }

    func testNonHttpSchemesAndSchemeLessTextAreUntouched() {
        for input in [
            "ftp://example.com/?utm_source=x",
            "www.example.com/?utm_source=x",
            "?utm_source=x"
        ] {
            assertClean(input, input, removed: 0)
        }
    }

    func testEmptyAndWhitespaceOnlyInputAreUntouched() {
        for input in ["", " ", "\n\t"] {
            assertClean(input, input, removed: 0)
        }
    }

    func testKnownClickIdentifiersAreRemovedButFunctionalReferrerIsKept() {
        assertClean(
            "https://example.com/?msclkid=a&gbraid=b&wbraid=c&mc_cid=d&mc_eid=e&ref=campaign",
            "https://example.com/?ref=campaign",
            removed: 5
        )
    }

    private func assertClean(
        _ input: String,
        _ expected: String,
        removed: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = cleaner.stripTrackingParameters(in: input)
        XCTAssertEqual(result.output, expected, file: file, line: line)
        XCTAssertEqual(result.changeCount, removed, file: file, line: line)
    }
}
