import XCTest
@testable import ClipGum

final class OfficeTableTests: XCTestCase {
    private let extractor = TableExtractionService()
    private let formatter = TableFormatter()

    func testMessyHTMLTableAndSemicolonLocalePreserveDecimalCommas() throws {
        let html = "<style>.x{color:red}</style><table style=\"background:red\"><thead><tr><th>Name</th><th>Amount</th></tr></thead><tbody><tr><td>Ada<br>Lovelace<script>bad()</script></td><td>12,50</td></tr><tr><td>Bob &amp; Co</td><td>7,00</td></tr></tbody></table>"
        let table = try extractor.extract(
            document: PasteboardDocument(html: html),
            plainText: ""
        )
        XCTAssertEqual(table.source, .html)
        XCTAssertEqual(table.rows, [
            ["Name", "Amount"],
            ["Ada\nLovelace", "12,50"],
            ["Bob & Co", "7,00"]
        ])
        XCTAssertEqual(table.detection, TableDetection(source: .html, rowCount: 3, columnCount: 2))

        let output = try formatter.format(
            table,
            options: TableConversionOptions(format: .csv, delimiter: .semicolon)
        )
        XCTAssertEqual(
            output,
            "Name;Amount\r\n\"Ada\nLovelace\";\"12,50\"\r\nBob & Co;\"7,00\""
        )
        XCTAssertFalse(output.contains("bad()"))
        XCTAssertEqual(try DelimitedTextParser().parse(output, delimiter: ";"), table.rows)
    }

    func testRFC4180CommaCSVQuotesCommasQuotesAndEmbeddedLineBreaks() throws {
        let table = TableDocument(rows: [
            ["Name", "Note"],
            ["Ada", "Hello, \"world\""],
            ["Bob", "line1\nline2"]
        ], source: .tsv)
        let output = try formatter.format(
            table,
            options: TableConversionOptions(format: .csv, delimiter: .comma)
        )
        XCTAssertEqual(
            output,
            "Name,Note\r\nAda,\"Hello, \"\"world\"\"\"\r\nBob,\"line1\nline2\""
        )
        XCTAssertEqual(try DelimitedTextParser().parse(output, delimiter: ","), table.rows)
        XCTAssertEqual(output, try formatter.format(
            table,
            options: TableConversionOptions(format: .csv, delimiter: .comma)
        ))
    }

    func testSemicolonExtractionDoesNotTreatDecimalCommasAsDelimiters() throws {
        let input = "Name;Amount\r\nAlice;12,50\r\nBob;1.234,56"
        let table = try extractor.extract(document: nil, plainText: input)
        XCTAssertEqual(table.source, .semicolonCSV)
        XCTAssertEqual(table.rows, [["Name", "Amount"], ["Alice", "12,50"], ["Bob", "1.234,56"]])
        let output = try formatter.format(
            table,
            options: TableConversionOptions(format: .csv, delimiter: .semicolon)
        )
        XCTAssertEqual(output, "Name;Amount\r\nAlice;\"12,50\"\r\nBob;\"1.234,56\"")
    }

    func testExcelTSVToMarkdownEscapesPipesAndQuotedNewlines() throws {
        let input = "Name\tNote\nAda\tA | B\nBob\t\"line1\nline2\""
        let table = try extractor.extract(document: nil, plainText: input)
        XCTAssertEqual(table.source, .tsv)
        let output = try formatter.format(
            table,
            options: TableConversionOptions(format: .markdown, delimiter: .comma)
        )
        XCTAssertEqual(
            output,
            "| Name | Note |\n| --- | --- |\n| Ada | A \\| B |\n| Bob | line1<br>line2 |"
        )
    }

    func testWhitespaceAlignedASCIIAndMarkdownAreDetected() throws {
        let ascii = "  Name    Amount\n  Ada     12,50\n  Bob     7,00"
        let asciiTable = try extractor.extract(document: nil, plainText: ascii)
        XCTAssertEqual(asciiTable.source, .alignedASCII)
        XCTAssertEqual(asciiTable.rows, [["Name", "Amount"], ["Ada", "12,50"], ["Bob", "7,00"]])

        let markdown = "| Name | Count |\n| :--- | ---: |\n| Ada | 2 |"
        let markdownTable = try extractor.extract(document: nil, plainText: markdown)
        XCTAssertEqual(markdownTable.source, .markdown)
        XCTAssertEqual(markdownTable.rows, [["Name", "Count"], ["Ada", "2"]])
        XCTAssertEqual(try formatter.format(
            markdownTable,
            options: TableConversionOptions(format: .csv, delimiter: .comma)
        ), "Name,Count\r\nAda,2")
    }

    func testHTMLSpansNestedTablesAndInconsistentRowsFailClosed() throws {
        XCTAssertThrowsError(try extractor.extract(
            document: PasteboardDocument(html: "<table><tr><td colspan=\"2\">x</td><td>y</td></tr></table>"),
            plainText: ""
        )) { error in
            XCTAssertEqual(error as? TableWorkflowError, .unsupportedSpan)
        }
        XCTAssertThrowsError(try extractor.extract(
            document: PasteboardDocument(html: "<table><tr><td><table><tr><td>x</td></tr></table></td></tr></table>"),
            plainText: ""
        )) { error in
            XCTAssertEqual(error as? TableWorkflowError, .nestedOrMultipleTables)
        }
        XCTAssertThrowsError(try extractor.extract(
            document: nil,
            plainText: "a\tb\n1"
        )) { error in
            XCTAssertEqual(error as? TableWorkflowError, .inconsistentColumns)
        }
    }

    func testMalformedDelimitedInputAndOrdinaryProseAreRejected() {
        XCTAssertThrowsError(try DelimitedTextParser().parse("a,\"unclosed", delimiter: ","))
        XCTAssertThrowsError(try extractor.extract(document: nil, plainText: "ordinary prose only")) { error in
            XCTAssertEqual(error as? TableWorkflowError, .noTable)
        }
    }
}
