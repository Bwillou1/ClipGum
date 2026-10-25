import XCTest
@testable import ClipGum

final class OutputValidatorTests: XCTestCase {
    private let validator = OutputValidator()
    private let sanitizer = OutputSanitizer()

    func testSanitizerRemovesOnlyKnownTransportWrappers() {
        XCTAssertEqual(
            sanitizer.sanitize(
                action: .correction,
                source: "teh text",
                output: "```text\nCorrected text:\nthe text\n```"
            ),
            "the text"
        )
        XCTAssertEqual(
            sanitizer.sanitize(
                action: .tableToCSV,
                source: "a\tb",
                output: "CSV:\na,b"
            ),
            "a,b"
        )
        XCTAssertEqual(
            sanitizer.sanitize(
                action: .correction,
                source: "Output: keep this genuine label.",
                output: "Output: keep this genuine label."
            ),
            "Output: keep this genuine label."
        )
    }

    func testUnchangedCorrectionPasses() {
        let report = validator.validate(
            action: .correction,
            source: "This is a stable sentence.",
            output: "This is a stable sentence."
        )
        XCTAssertTrue(report.canExport)
        XCTAssertTrue(report.issues.isEmpty)
    }

    func testChangedAndInventedNumbersAreBlocked() {
        for output in ["Version 2 is stable.", "Version 1 is stable for 3 users."] {
            let report = validator.validate(
                action: .correction,
                source: "Version 1 is stable.",
                output: output
            )
            XCTAssertTrue(report.errors.contains { $0.code == .numbersChanged })
            XCTAssertFalse(report.canExport)
        }
    }

    func testRewriteMustPreserveNumbers() {
        let report = validator.validate(
            action: .rewrite,
            source: "Our release 2 is ready for customers.",
            output: "Our release 3 is ready for customers."
        )
        XCTAssertTrue(report.errors.contains { $0.code == .numbersChanged })
    }

    func testConciseRewriteWithSameNumbersCanPass() {
        let report = validator.validate(
            action: .rewrite,
            source: "Our release 2 is ready for customers.",
            output: "Release 2 is ready for customers."
        )
        XCTAssertTrue(report.canExport)
    }

    func testChangedFencedCodeIsBlocked() {
        let source = "Fix prose only.\n```swift\nlet answer = 42\n```"
        let output = "Fix prose only.\n```swift\nlet answer = 43\n```"
        let report = validator.validate(action: .correction, source: source, output: output)
        XCTAssertTrue(report.errors.contains { $0.code == .codeChanged })
        XCTAssertTrue(report.errors.contains { $0.code == .numbersChanged })
    }

    func testPreservedFencedAndInlineCodePassStructuralChecks() {
        let text = "Use `let count = 2` exactly.\n```swift\nprint(2)\n```"
        let report = validator.validate(action: .correction, source: text, output: text)
        XCTAssertFalse(report.errors.contains { $0.code == .codeChanged })
        XCTAssertFalse(report.errors.contains { $0.code == .numbersChanged })
    }

    func testRegeneratedAWSSecretIsBlocked() {
        let report = validator.validate(
            action: .correction,
            source: "credential=\(RuleCleaningService.redactionPlaceholder)",
            output: "credential=AKIAIOSFODNN7EXAMPLE"
        )
        XCTAssertTrue(report.errors.contains { $0.code == .secretRegenerated })
        XCTAssertFalse(report.canExport)
    }

    func testRegeneratedGenericSecretIsBlocked() {
        let report = validator.validate(
            action: .rewrite,
            source: "token=\(RuleCleaningService.redactionPlaceholder)",
            output: "token=Abcd1234efgh5678"
        )
        XCTAssertTrue(report.errors.contains { $0.code == .secretRegenerated })
    }

    func testLostRedactionMarkerIsBlocked() {
        let report = validator.validate(
            action: .correction,
            source: "token=\(RuleCleaningService.redactionPlaceholder)",
            output: "token=hidden"
        )
        XCTAssertTrue(report.errors.contains { $0.code == .missingRedactionMarker })
    }

    func testLargeSemanticDivergenceIsBlocked() {
        let report = validator.validate(
            action: .correction,
            source: "alpha bravo charlie delta echo foxtrot",
            output: "alpha zulu zebra yank quartz nebula"
        )
        XCTAssertTrue(report.errors.contains { $0.code == .semanticDivergence })
    }

    func testModerateSemanticDivergenceIsAReviewWarning() {
        let report = validator.validate(
            action: .correction,
            source: "alpha bravo charlie delta echo foxtrot",
            output: "alpha bravo charlie zulu zebra yank"
        )
        XCTAssertTrue(report.warnings.contains { $0.code == .semanticDivergence })
        XCTAssertTrue(report.canExport)
    }

    func testEmptyAndControlCharacterOutputsAreBlocked() {
        XCTAssertEqual(
            validator.validate(action: .correction, source: "text", output: "").errors.first?.code,
            .emptyOutput
        )
        let control = validator.validate(
            action: .correction,
            source: "text",
            output: "bad\0text"
        )
        XCTAssertTrue(control.errors.contains { $0.code == .invalidControlCharacter })
    }

    func testValidTSVToCSVWithQuotedCommaPasses() {
        let report = validator.validate(
            action: .tableToCSV,
            source: "Name\tNote\nAda\tHello, world",
            output: "Name,Note\nAda,\"Hello, world\""
        )
        XCTAssertTrue(report.canExport)
        XCTAssertTrue(report.issues.isEmpty)
    }

    func testMarkdownTableToCSVSkipsOnlySeparatorRow() {
        let report = validator.validate(
            action: .tableToCSV,
            source: "| Name | Count |\n| --- | ---: |\n| Ada | 2 |",
            output: "Name,Count\nAda,2"
        )
        XCTAssertTrue(report.canExport)
    }

    func testChangedCSVCellIsBlocked() {
        let report = validator.validate(
            action: .tableToCSV,
            source: "Name\tCount\nAda\t2",
            output: "Name,Count\nAda,3"
        )
        XCTAssertTrue(report.errors.contains { $0.code == .tableDataChanged })
    }

    func testMisalignedCSVIsBlocked() {
        let report = validator.validate(
            action: .tableToCSV,
            source: "Name\tCount\nAda\t2",
            output: "Name,Count\nAda"
        )
        XCTAssertTrue(report.errors.contains { $0.code == .invalidCSV })
    }

    func testUnsupportedTableInputFailsClosed() {
        let report = validator.validate(
            action: .tableToCSV,
            source: "not a table",
            output: "not,a,table"
        )
        XCTAssertTrue(report.errors.contains { $0.code == .invalidTableSchema })
    }

    func testCSVParserHandlesEscapedQuotesCRLFAndQuotedNewlines() throws {
        let csv = try CSVDocument.parse("a,b\r\n\"x,\"\"y\"\"\",\"line1\nline2\"\r\n")
        XCTAssertEqual(csv.rows, [["a", "b"], ["x,\"y\"", "line1\nline2"]])
    }

    func testCSVParserRejectsUnclosedQuote() {
        XCTAssertThrowsError(try CSVDocument.parse("a,\"unclosed"))
    }

    func testTableExtractorPreservesEmptyTSVCells() throws {
        let rows = try TableDataExtractor().rows(from: "a\t\tc\n1\t2\t3")
        XCTAssertEqual(rows, [["a", "", "c"], ["1", "2", "3"]])
    }
}
