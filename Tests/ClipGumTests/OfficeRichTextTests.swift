import AppKit
import XCTest
@testable import ClipGum

@MainActor
final class OfficeRichTextTests: XCTestCase {
    func testRealWorldPDFRepairPreservesParagraphsAndAccents() {
        let input = """
        Le dével-
        oppement durable est décrit
        sur deux lignes.

        Deuxième paragraphe avec café
        et déjà-vu.
        """
        let output = PDFArtifactRepair().repair(input)
        XCTAssertEqual(
            output,
            "Le développement durable est décrit sur deux lignes.\n\nDeuxième paragraphe avec café et déjà-vu."
        )
        XCTAssertFalse(output.contains("dével-"))
        XCTAssertEqual(output.components(separatedBy: "\n\n").count, 2)
    }

    func testPDFRepairRetainsListStartsAndCRLFParagraphBoundaries() {
        let input = "Intro line\r\ncontinues here\r\n\r\n- first item\r\n- second item"
        XCTAssertEqual(
            PDFArtifactRepair().repair(input),
            "Intro line continues here\n\n- first item\n- second item"
        )
    }

    func testMessyBrowserHTMLPreservesOnlySemanticFormatting() throws {
        let input = "<html><head><title>Ignore title</title><style>body{background:url(x)}</style><script>alert(1)</script></head><body><div style=\"font-family:Papyrus;background:red\"><h1 style=\"font-size:70px\">Report</h1><h2>Section</h2><h3>Detail</h3><p><strong>Bold</strong> and <em>italic</em> <a href=\"https://example.com?a=1&amp;b=2\" style=\"color:red\">safe link</a></p><ul><li>First</li></ul><ol><li>Second</li></ol><p><font face=\"Papyrus\">Café &amp; crème</font></p><a href=\"javascript:alert(1)\">unsafe link</a><script>discardMe()</script></div></body></html>"
        let html = try HTMLSemanticProcessor().sanitizedHTML(from: input)

        for tag in ["<h1>Report</h1>", "<h2>Section</h2>", "<h3>Detail</h3>", "<strong>Bold</strong>", "<em>italic</em>", "<ul><li>First</li></ul>", "<ol><li>Second</li></ol>"] {
            XCTAssertTrue(html.contains(tag), "Missing \(tag) in \(html)")
        }
        XCTAssertTrue(html.contains("<a href=\"https://example.com?a=1&amp;b=2\">safe link</a>"))
        XCTAssertTrue(html.contains("<a>unsafe link</a>"))
        XCTAssertTrue(html.contains("Café &amp; crème"))
        for rejected in ["style=", "background", "font-family", "Papyrus", "javascript:", "alert(1)", "discardMe", "Ignore title", "<font", "<div"] {
            XCTAssertFalse(html.contains(rejected), "Unexpected \(rejected) in \(html)")
        }
    }

    func testHTMLScannerEscapesMalformedTextAndBalancesAllowedTags() throws {
        let processor = HTMLSemanticProcessor()
        let html = try processor.sanitizedHTML(from: "2 < 3 & <broken")
        let balanced = try processor.sanitizedHTML(from: "<b><i>x</b>y")
        XCTAssertTrue(html.contains("2 &lt; 3 &amp;"))
        XCTAssertTrue(html.contains("&lt;broken"))
        XCTAssertEqual(balanced, "<b><i>x</i></b>y")
        XCTAssertFalse(html.contains("<script"))
    }

    func testHTMLPlainTextDropsScriptsAndKeepsAccentsAndCells() throws {
        let text = try HTMLSemanticProcessor().plainText(
            from: "<p>Caf&eacute; &amp; th&eacute;</p><script>secret()</script><table><tr><td>A</td><td>B</td></tr></table>"
        )
        XCTAssertEqual(text, "Café & thé\nA\tB")
        XCTAssertFalse(text.contains("secret"))
    }

    func testAppKitRTFRoundTripPreservesBoldItalicAndLink() throws {
        let source = NSMutableAttributedString(string: "Bold italic")
        source.addAttribute(
            .font,
            value: NSFont.boldSystemFont(ofSize: 14),
            range: NSRange(location: 0, length: 4)
        )
        let regular = NSFont.systemFont(ofSize: 14)
        let italic = NSFontManager.shared.convert(regular, toHaveTrait: .italicFont)
        source.addAttribute(.font, value: italic, range: NSRange(location: 5, length: 6))
        source.addAttribute(
            .link,
            value: URL(string: "https://example.com")!,
            range: NSRange(location: 5, length: 6)
        )
        let rtf = try source.data(
            from: NSRange(location: 0, length: source.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )

        let result = try RichTextSanitizer().sanitize(
            document: PasteboardDocument(rtfData: rtf)
        )
        XCTAssertEqual(result.plainText, "Bold italic")
        XCTAssertNotNil(result.payload.html)
        let outputRTF = try XCTUnwrap(result.payload.rtfData)
        let roundTrip = try AppKitRichTextSerializer().attributedString(fromRTF: outputRTF)
        XCTAssertEqual(
            roundTrip.string.trimmingCharacters(in: .whitespacesAndNewlines),
            "Bold italic"
        )
        let boldFont = try XCTUnwrap(roundTrip.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let italicFont = try XCTUnwrap(roundTrip.attribute(.font, at: 5, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(boldFont.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertTrue(italicFont.fontDescriptor.symbolicTraits.contains(.italic))
        XCTAssertNotNil(roundTrip.attribute(.link, at: 5, effectiveRange: nil))
    }

    func testSanitizedPayloadStripsForeignTypographyBeforeRTFSerialization() throws {
        let result = try RichTextSanitizer().sanitize(
            document: PasteboardDocument(
                plainText: "Styled café",
                html: "<p style=\"font-family:Papyrus;background:yellow\">Styled <strong>café</strong></p>"
            )
        )
        let rtf = try XCTUnwrap(result.payload.rtfData)
        let rtfSource = String(decoding: rtf, as: UTF8.self)
        XCTAssertFalse(rtfSource.contains("Papyrus"))
        XCTAssertFalse(result.sanitizedHTML.contains("style="))
        XCTAssertEqual(result.payload.plainText, "Styled café")
    }

    func testPlainOnlyDocumentCannotProduceARichPayload() {
        XCTAssertThrowsError(try RichTextSanitizer().sanitize(
            document: PasteboardDocument(plainText: "plain")
        )) { error in
            XCTAssertEqual(error as? RichTextWorkflowError, .noRichText)
        }
    }
}
