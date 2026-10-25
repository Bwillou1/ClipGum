import XCTest
@testable import ClipGum

final class LogScrubberTests: XCTestCase {
    private let scrubber = LogScrubber()

    func testANSIFramesTimestampsAndLocalIPsAreRemoved() {
        let input = "\u{1B}[31m[2024-01-02T03:04:05Z] ERROR\u{1B}[0m private=10.0.0.1 local=127.0.0.1 public=8.8.8.8\n    at com.example.App.run(App.java:42)\n"
        let result = scrubber.scrub(input)
        XCTAssertEqual(
            result.output,
            "ERROR private=[SECRET_REDACTED] local=[SECRET_REDACTED] public=8.8.8.8\n"
        )
        XCTAssertEqual(result.removedStackFrames, 1)
        XCTAssertEqual(result.removedTimestamps, 1)
        XCTAssertEqual(result.redactedSecrets, 2)
    }

    func testOSCAndPythonFrameRemoval() {
        let input = "\u{1B}]0;window title\u{7}Jan  2 03:04:05 failed\n  File \"/tmp/a.py\", line 3, in run\n::1 fe80::1"
        let result = scrubber.scrub(input)
        XCTAssertFalse(result.output.contains("window title"))
        XCTAssertFalse(result.output.contains("File "))
        XCTAssertEqual(result.output, "failed\n[SECRET_REDACTED] [SECRET_REDACTED]")
    }

    func testCRLFDoesNotCreateExtraBlankLines() {
        let result = scrubber.scrub("12:34:56 one\r\nat /tmp/a.js:1:2\r\n12:34:57 two")
        XCTAssertEqual(result.output, "one\ntwo")
        XCTAssertEqual(result.removedTimestamps, 2)
        XCTAssertEqual(result.removedStackFrames, 1)
    }

    func testExistingExactSecretMarkerIsPreserved() {
        let result = scrubber.scrub("token=Abcd1234efgh5678 169.254.1.2")
        XCTAssertEqual(
            result.output,
            "token=[SECRET_REDACTED] [SECRET_REDACTED]"
        )
    }
}
