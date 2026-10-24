import XCTest
@testable import ClipGum

final class ShareReadySessionTests: XCTestCase {
    func testMappingsAreConsistentAndRoundTrip() {
        let session = ShareReadySession()
        let input = """
        hosts=10.0.0.1,172.16.2.3,192.168.1.4,8.8.8.8
        local=localhost,::1
        endpoints=api.corp,service.internal,db.corp.net
        path=/Users/alice/project/file.swift
        API_KEY=supersecretvalue
        Authorization: Bearer abcdef123456
        again=10.0.0.1,/Users/alice/project
        """
        let first = session.anonymize(input)
        let second = session.anonymize(input)
        XCTAssertEqual(first.output, second.output)
        XCTAssertEqual(first.mappingCount, second.mappingCount)
        XCTAssertGreaterThanOrEqual(first.replacementCount, 10)
        XCTAssertTrue(first.output.contains("host-1.example.test"))
        XCTAssertTrue(first.output.contains("db.example.test"))
        XCTAssertTrue(first.output.contains("/Users/[USER]/project/file.swift"))
        XCTAssertTrue(first.output.contains("8.8.8.8"))
        XCTAssertFalse(first.output.contains("10.0.0.1"))
        XCTAssertFalse(first.output.contains("supersecretvalue"))
        XCTAssertFalse(first.output.contains("abcdef123456"))
        XCTAssertEqual(session.restore(first.output).output, input)
    }

    func testRestoreCanTargetReturnedAssistantSnippetOnly() {
        let session = ShareReadySession()
        let anonymized = session.anonymize("connect db.corp.net and /Users/alice/app")
        let assistant = "Use \(anonymized.output); do not change unrelated text."
        let restored = session.restore(assistant)
        XCTAssertEqual(
            restored.output,
            "Use connect db.corp.net and /Users/[USER]/app; do not change unrelated text."
                .replacingOccurrences(of: "/Users/[USER]", with: "/Users/alice")
        )
        XCTAssertEqual(restored.replacementCount, 2)
    }

    func testSyntheticCollisionAvoidance() {
        let session = ShareReadySession()
        let input = "/Users/[USER] /Users/alice"
        let result = session.anonymize(input)
        XCTAssertTrue(result.output.contains("/Users/[USER_2]"))
        XCTAssertEqual(session.restore(result.output).output, input)
    }

    func testPublicAndMalformedIPAddressesAreNotChanged() {
        let session = ShareReadySession()
        let input = "8.8.8.8 172.15.0.1 172.32.0.1 999.10.1.1 10.0.0.999"
        XCTAssertEqual(session.anonymize(input).output, input)
        XCTAssertEqual(session.mappingCount, 0)
    }

    func testClearDropsBothMappingDirectionsAndOrdinals() {
        let session = ShareReadySession()
        let first = session.anonymize("10.0.0.1")
        XCTAssertEqual(first.output, "host-1.example.test")
        XCTAssertEqual(session.originalValue(for: first.output), "10.0.0.1")
        session.clear()
        XCTAssertEqual(session.mappingCount, 0)
        XCTAssertNil(session.originalValue(for: first.output))
        XCTAssertNil(session.syntheticValue(for: "10.0.0.1", category: .privateIP))
        XCTAssertEqual(session.restore(first.output).output, first.output)
        XCTAssertEqual(session.anonymize("10.0.0.1").output, "host-1.example.test")
    }

    func testPrivateKeyAndBasicCredentialsRoundTrip() {
        let session = ShareReadySession()
        let key = "-----BEGIN PRIVATE KEY-----\nabc123\n-----END PRIVATE KEY-----"
        let input = "https://user:password@example.com \(key) {\"password\":\"jsonsecret\"}"
        let anonymized = session.anonymize(input)
        XCTAssertFalse(anonymized.output.contains("user:password"))
        XCTAssertFalse(anonymized.output.contains("abc123"))
        XCTAssertFalse(anonymized.output.contains("jsonsecret"))
        XCTAssertEqual(session.restore(anonymized.output).output, input)
    }
}
