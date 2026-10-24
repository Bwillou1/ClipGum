import XCTest
@testable import ClipGum

final class InlineDiffTests: XCTestCase {
    func testIdenticalTextIsOneUnchangedSegment() {
        XCTAssertEqual(
            InlineDiff.segments(before: "same text", after: "same text"),
            [InlineDiffSegment(kind: .unchanged, text: "same text")]
        )
    }

    func testInsertionIsExactAndReconstructable() {
        let segments = InlineDiff.segments(before: "alpha gamma", after: "alpha beta gamma")
        XCTAssertTrue(segments.contains { $0.kind == .insertion && $0.text.contains("beta") })
        XCTAssertEqual(reconstruct(segments, kinds: [.unchanged, .insertion]), "alpha beta gamma")
        XCTAssertEqual(reconstruct(segments, kinds: [.unchanged, .removal]), "alpha gamma")
    }

    func testRemovalIsExactAndReconstructable() {
        let segments = InlineDiff.segments(before: "alpha beta gamma", after: "alpha gamma")
        XCTAssertTrue(segments.contains { $0.kind == .removal && $0.text.contains("beta") })
        XCTAssertEqual(reconstruct(segments, kinds: [.unchanged, .insertion]), "alpha gamma")
        XCTAssertEqual(reconstruct(segments, kinds: [.unchanged, .removal]), "alpha beta gamma")
    }

    func testReplacementContainsBothRemovalAndInsertion() {
        let segments = InlineDiff.segments(before: "version 1", after: "version 2")
        XCTAssertTrue(segments.contains { $0.kind == .removal && $0.text.contains("1") })
        XCTAssertTrue(segments.contains { $0.kind == .insertion && $0.text.contains("2") })
    }

    func testWhitespaceAndPunctuationAreNeverDropped() {
        let before = "a  b\n\tc!"
        let after = "a b\n\tc? "
        let segments = InlineDiff.segments(before: before, after: after)
        XCTAssertEqual(reconstruct(segments, kinds: [.unchanged, .removal]), before)
        XCTAssertEqual(reconstruct(segments, kinds: [.unchanged, .insertion]), after)
    }

    func testUnicodeTokensRoundTripExactly() {
        let before = "Café 👋 — 10.0.0.1"
        let after = "Café 👋 — [SECRET_REDACTED] 42"
        let segments = InlineDiff.segments(before: before, after: after)
        XCTAssertEqual(reconstruct(segments, kinds: [.unchanged, .removal]), before)
        XCTAssertEqual(reconstruct(segments, kinds: [.unchanged, .insertion]), after)
    }

    func testTokenizerPreservesEverySourceByteAsText() {
        let samples = ["", " ", "a\r\nb", "emoji🙂token", "JSON: {\"a\":1}"]
        for sample in samples {
            XCTAssertEqual(InlineDiff.tokens(in: sample).joined(), sample)
        }
    }

    private func reconstruct(
        _ segments: [InlineDiffSegment],
        kinds: Set<InlineDiffSegment.Kind>
    ) -> String {
        segments.filter { kinds.contains($0.kind) }.map(\.text).joined()
    }
}
