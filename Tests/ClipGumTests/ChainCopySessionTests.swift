import XCTest
@testable import ClipGum

final class ChainCopySessionTests: XCTestCase {
    func testOptInAccumulationAndExactDuplicateFiltering() {
        var session = ChainCopySession()
        XCTAssertEqual(session.add("not started"), .inactive)
        XCTAssertEqual(session.start(with: "alpha"), .added)
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.add("alpha"), .duplicate)
        XCTAssertEqual(session.add("beta"), .added)
        XCTAssertEqual(session.add("alpha "), .added)
        XCTAssertEqual(session.items.count, 3)
        XCTAssertEqual(session.combinedPreview, "alpha\nbeta\nalpha ")
    }

    func testSelectionReorderingAndDelimitersUpdatePreview() {
        var session = ChainCopySession()
        session.start(with: "one")
        session.add("two")
        session.add("three")
        let first = session.items[0].id
        let second = session.items[1].id

        session.setDelimiter(.comma)
        XCTAssertEqual(session.combinedPreview, "one,two,three")
        session.toggleInclusion(id: second)
        XCTAssertEqual(session.combinedPreview, "one,three")
        XCTAssertEqual(session.add("two"), .duplicate, "Excluded duplicates are still filtered")

        session.move(id: first, direction: .down)
        XCTAssertEqual(session.items.map(\.text), ["two", "one", "three"])
        session.setDelimiter(.markdownBullets)
        XCTAssertEqual(session.combinedPreview, "- one\n- three")
        session.setAllIncluded(true)
        XCTAssertEqual(session.combinedPreview, "- two\n- one\n- three")
        session.setAllIncluded(false)
        XCTAssertEqual(session.combinedPreview, "")
    }

    func testMoveBoundariesAndUnknownIDsAreSafe() {
        var session = ChainCopySession()
        session.start(with: "one")
        session.add("two")
        let first = session.items[0].id
        let last = session.items[1].id
        session.move(id: first, direction: .up)
        session.move(id: last, direction: .down)
        session.move(id: 999, direction: .down)
        session.toggleInclusion(id: 999)
        XCTAssertEqual(session.items.map(\.text), ["one", "two"])
    }

    func testClearDropsClipsAndRequiresNewOptIn() {
        var session = ChainCopySession()
        session.start(with: "sensitive clip")
        session.clear()
        XCTAssertFalse(session.isActive)
        XCTAssertTrue(session.items.isEmpty)
        XCTAssertEqual(session.combinedPreview, "")
        XCTAssertEqual(session.add("another"), .inactive)
    }
}
