import Foundation
import XCTest
@testable import ClipGum

@MainActor
final class OfficeAppProfileTests: XCTestCase {
    func testFrontmostBundleIdentifiersMapToOfficeProfiles() {
        let cases: [(String?, OfficeAppKind)] = [
            ("com.microsoft.word", .word),
            ("com.microsoft.excel", .excel),
            ("com.microsoft.outlook", .outlook),
            ("com.apple.mail", .mail),
            ("com.tinyspeck.slackmacgap", .slack),
            ("com.apple.safari", .browser),
            ("com.google.chrome", .browser),
            ("org.mozilla.firefox", .browser),
            ("com.example.unknown", .other),
            (nil, .other)
        ]
        for (bundle, kind) in cases {
            XCTAssertEqual(
                OfficeAppProfileResolver.profile(
                    bundleIdentifier: bundle,
                    localizedName: nil
                ).kind,
                kind,
                bundle ?? "nil"
            )
        }
        XCTAssertEqual(
            OfficeAppProfileResolver.profile(
                bundleIdentifier: nil,
                localizedName: "Mozilla Firefox"
            ).kind,
            .browser
        )
    }

    func testProfilesSuggestRelevantActionsWithoutExecutingThem() {
        XCTAssertEqual(OfficeAppProfileResolver.profile(
            bundleIdentifier: "com.microsoft.word",
            localizedName: "Word"
        ).suggestedActions, [.sanitizeRichText, .repairPDF, .correction])
        XCTAssertEqual(OfficeAppProfileResolver.profile(
            bundleIdentifier: "com.microsoft.outlook",
            localizedName: "Outlook"
        ).suggestedActions, [.professionalEmail, .correction])
        XCTAssertTrue(OfficeAppProfileResolver.profile(
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            localizedName: "Slack"
        ).suggestedActions.contains(.slackSummary))
    }

    func testPaletteExposesOnlySupportedSuggestionsAndTableOptions() {
        let original = "Name\tAmount\nAda\t12,50"
        let html = "<table><tr><th>Name</th><th>Amount</th></tr><tr><td>Ada</td><td>12,50</td></tr></table>"
        let baseline = CleaningResult(
            original: original,
            cleaned: original,
            removedTrackingParameters: 0,
            redactedSecrets: 0
        )
        let profile = OfficeAppProfileResolver.profile(
            bundleIdentifier: "com.microsoft.excel",
            localizedName: "Microsoft Excel"
        )
        let model = PaletteModel(
            content: .preview(PalettePreview(deterministicResult: baseline)),
            document: PasteboardDocument(plainText: original, html: html),
            appProfile: profile
        )
        XCTAssertEqual(model.tableDetection, TableDetection(source: .html, rowCount: 2, columnCount: 2))
        XCTAssertTrue(model.availableActions.contains(.convertTable))
        XCTAssertTrue(model.availableActions.contains(.sanitizeRichText))
        XCTAssertEqual(model.suggestedActions, [.convertTable, .tableToCSV])
        XCTAssertEqual(model.selectedAction, .clean)

        model.tableFormat = .markdown
        model.tableDelimiter = .semicolon
        XCTAssertEqual(model.developerOptions.table.format, .markdown)
        XCTAssertEqual(model.developerOptions.table.delimiter, .semicolon)
    }

    func testRichExportRequiresPayloadPlainTextToMatchVisibleOutput() {
        let payload = PasteboardPayload(plainText: "safe", html: "<b>safe</b>", rtfData: Data([1]))
        let result = CleaningResult(
            original: "safe",
            cleaned: "safe",
            removedTrackingParameters: 0,
            redactedSecrets: 0,
            pasteboardPayload: payload
        )
        var preview = PalettePreview(deterministicResult: result, action: .sanitizeRichText)
        XCTAssertEqual(preview.exportPayload, payload)
        preview.output = "different"
        XCTAssertNil(preview.exportPayload)
    }
}
