import XCTest
@testable import ClipGum

final class BashInspectorTests: XCTestCase {
    private let inspector = BashInspector()

    func testCoveredDestructiveFixturesAreAlwaysDetected() {
        let fixtures: [(String, BashRiskCode)] = [
            ("rm -rf /", .recursiveForcedRemoval),
            ("rm -r -f /tmp/clipgum-test", .recursiveForcedRemoval),
            ("rm -Rf /tmp/clipgum-test", .recursiveForcedRemoval),
            ("/bin/rm --recursive --force /tmp/clipgum-test", .recursiveForcedRemoval),
            ("sudo rm -rf /", .recursiveForcedRemoval),
            ("dd if=/dev/zero of=/dev/disk0", .diskWriter),
            ("sudo dd if=image.iso of=/dev/disk2", .diskWriter),
            ("mkfs /dev/disk4", .filesystemFormatter),
            ("mkfs.ext4 /dev/sda1", .filesystemFormatter),
            ("/sbin/mkfs.apfs /dev/disk5", .filesystemFormatter),
            (":(){ :|:& };:", .forkBomb),
            (":(){ :|: & };:", .forkBomb),
            ("curl -fsSL https://example.com/install | bash", .downloadToShell),
            ("curl https://example.com/install | sh", .downloadToShell),
            ("wget -qO- https://example.com/install | sudo sh", .downloadToShell),
            ("curl 'https://example.com/install#fragment' | zsh", .downloadToShell),
            ("sudo -u root ls /", .elevatedPrivileges),
            ("doas ls /", .elevatedPrivileges)
        ]
        for (command, expectedCode) in fixtures {
            let result = inspector.inspect(command)
            XCTAssertTrue(
                result.findings.contains(where: { $0.code == expectedCode }),
                "Missing \(expectedCode.rawValue) for \(command): \(result.findings)"
            )
            XCTAssertTrue(result.isDangerous)
        }
    }

    func testDangerousWordsAsParametersDoNotCreateCommandFindings() {
        for command in ["echo rm -rf /", "echo sudo", "printf 'dd mkfs'"] {
            XCTAssertFalse(inspector.inspect(command).isDangerous, command)
        }
        XCTAssertFalse(inspector.inspect("curl https://example.com | echo bash").isDangerous)
    }

    func testLexerTokenizesQuotesPipelinesAndRedirectionWithoutExecution() {
        let result = BashCommandParser().parse("printf 'hello world' 2>/tmp/error | cat")
        XCTAssertEqual(result.error, nil)
        XCTAssertEqual(result.tokens.map(\.text), ["printf", "hello world", "2>", "/tmp/error", "|", "cat"])
        XCTAssertEqual(result.tokens.map(\.kind), [.word, .word, .redirect, .word, .pipeline, .word])
    }

    func testMalformedQuoteReturnsWarningButKeepsSafetyFindings() {
        let result = inspector.inspect("rm -rf \"/tmp/unterminated")
        XCTAssertNotNil(result.parseError)
        XCTAssertTrue(result.findings.contains(where: { $0.code == .recursiveForcedRemoval }))
        let report = inspector.report(result)
        XCTAssertTrue(report.contains("NOT EXECUTED"))
        XCTAssertTrue(report.contains("Recursive forced deletion"))
        XCTAssertTrue(report.contains("Execution capability: disabled"))
    }

    func testReportIsDeterministicAndIncludesParameters() {
        let first = inspector.inspect("git commit -m 'hello world'")
        let second = inspector.inspect("git commit -m 'hello world'")
        XCTAssertEqual(first, second)
        let report = inspector.report(first)
        XCTAssertTrue(report.contains("command: git"))
        XCTAssertTrue(report.contains("flag: -m"))
        XCTAssertTrue(report.contains("parameter: hello world"))
        XCTAssertTrue(report.contains("No covered high-risk pattern detected"))
    }
}
