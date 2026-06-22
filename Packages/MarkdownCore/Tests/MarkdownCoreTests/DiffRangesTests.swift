import XCTest
@testable import MarkdownCore

final class DiffRangesTests: XCTestCase {

    private func sub(_ s: String, _ r: NSRange) -> String { (s as NSString).substring(with: r) }

    func testIdenticalIsEmpty() {
        XCTAssertEqual(DiffRanges.changedLineRanges(from: "a\nb\nc\n", to: "a\nb\nc\n"), [])
    }

    func testModifiedMiddleLine() {
        let old = "alpha\nbeta\ngamma\n"
        let new = "alpha\nBETA CHANGED\ngamma\n"
        let ranges = DiffRanges.changedLineRanges(from: old, to: new)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(sub(new, ranges[0]), "BETA CHANGED")
    }

    func testAppendedLines() {
        let old = "one\ntwo\n"
        let new = "one\ntwo\nthree\nfour\n"
        let ranges = DiffRanges.changedLineRanges(from: old, to: new)
        // three + four are contiguous -> merged into one span covering both.
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(sub(new, ranges[0]), "three\nfour")
    }

    func testCyrillicOffsetsStayAligned() {
        let old = "привет\nмир\n"
        let new = "привет\nдобрый мир\n"
        let ranges = DiffRanges.changedLineRanges(from: old, to: new)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(sub(new, ranges[0]), "добрый мир")
    }

    func testEmojiOffsetsStayAligned() {
        let old = "line 🚀 one\nplain\n"
        let new = "line 🚀 one\nplain edited 😀\n"
        let ranges = DiffRanges.changedLineRanges(from: old, to: new)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(sub(new, ranges[0]), "plain edited 😀")
    }

    func testTwoSeparateChangesNotMerged() {
        let old = "a\nb\nc\nd\ne\n"
        let new = "A\nb\nc\nd\nE\n"   // first and last lines changed, middle intact
        let ranges = DiffRanges.changedLineRanges(from: old, to: new)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(sub(new, ranges[0]), "A")
        XCTAssertEqual(sub(new, ranges[1]), "E")
    }

    func testInsertionInMiddle() {
        let old = "a\nc\n"
        let new = "a\nb\nc\n"
        let ranges = DiffRanges.changedLineRanges(from: old, to: new)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(sub(new, ranges[0]), "b")
    }
}
