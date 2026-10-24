import AppKit
import XCTest
@testable import ClipGum

@MainActor
final class PasteServiceTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var systemPasteboard: SystemPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipGumTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("original", forType: .string))
        systemPasteboard = SystemPasteboard(pasteboard: pasteboard)
    }

    override func tearDown() {
        pasteboard.clearContents()
        systemPasteboard = nil
        pasteboard = nil
        super.tearDown()
    }

    func testDeniedAccessibilityDoesNotWriteActivateOrPost() {
        let changeCount = pasteboard.changeCount
        let service = PasteService(
            pasteboard: systemPasteboard,
            accessibilityTrusted: { prompt in
                XCTAssertTrue(prompt)
                return false
            },
            applicationActivator: { _ in
                XCTFail("Must not activate an app after permission denial")
            },
            keystrokePoster: {
                XCTFail("Must not post ⌘V after permission denial")
            },
            focusSettleDelay: 0
        )

        XCTAssertThrowsError(try service.paste("cleaned", to: nil)) { error in
            guard
                let pasteError = error as? PasteServiceError,
                case .accessibilityRequired = pasteError
            else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(pasteboard.changeCount, changeCount)
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

    func testCopyResultNeedsNoAccessibilityAndWritesExplicitly() {
        let service = PasteService(
            pasteboard: systemPasteboard,
            accessibilityTrusted: { _ in
                XCTFail("Copy must not request Accessibility")
                return false
            },
            applicationActivator: { _ in
                XCTFail("Copy must not activate an app")
            },
            keystrokePoster: {
                XCTFail("Copy must not post a keystroke")
            },
            focusSettleDelay: 0
        )

        XCTAssertNoThrow(try service.copyResult("cleaned"))
        XCTAssertEqual(pasteboard.string(forType: .string), "cleaned")
    }

    func testTrustedPasteWritesThenActivatesAndPostsOnce() {
        let activationExpectation = expectation(description: "target activated")
        let posterExpectation = expectation(description: "⌘V posted once")
        let service = PasteService(
            pasteboard: systemPasteboard,
            accessibilityTrusted: { _ in true },
            applicationActivator: { _ in
                activationExpectation.fulfill()
            },
            keystrokePoster: {
                posterExpectation.fulfill()
            },
            focusSettleDelay: 0
        )

        XCTAssertNoThrow(try service.paste("cleaned", to: nil))

        XCTAssertEqual(pasteboard.string(forType: .string), "cleaned")
        wait(for: [activationExpectation, posterExpectation], timeout: 1)
    }

    func testNonActionCodePathCannotWriteThroughPasteService() {
        // Construction alone must be inert; only copyResult/paste are write APIs.
        let changeCount = pasteboard.changeCount
        _ = PasteService(
            pasteboard: systemPasteboard,
            accessibilityTrusted: { _ in false },
            applicationActivator: { _ in XCTFail() },
            keystrokePoster: { XCTFail() }
        )

        XCTAssertEqual(pasteboard.changeCount, changeCount)
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }
}
