import XCTest
@testable import MarkdownCore

final class MarkupCollapseTests: XCTestCase {

    func testRemovesBoldMarkers() {
        let s = NSAttributedString(string: "**bold**")
        let out = MarkupCollapse.collapsed(s, hiding: [
            NSRange(location: 0, length: 2),   // leading **
            NSRange(location: 6, length: 2),   // trailing **
        ])
        XCTAssertEqual(out.string, "bold")
    }

    func testRemovesHeadingHash() {
        let s = NSAttributedString(string: "# Title")
        // hide "# " (hash + space) -> "Title"
        let out = MarkupCollapse.collapsed(s, hiding: [NSRange(location: 0, length: 2)])
        XCTAssertEqual(out.string, "Title")
    }

    func testMultipleMarkersStayAligned() {
        // "a **b** `c`" -> hide the **, **, `, ` -> "a b c"
        let s = NSAttributedString(string: "a **b** `c`")
        let out = MarkupCollapse.collapsed(s, hiding: [
            NSRange(location: 2, length: 2),   // **
            NSRange(location: 5, length: 2),   // **
            NSRange(location: 8, length: 1),   // `
            NSRange(location: 10, length: 1),  // `
        ])
        XCTAssertEqual(out.string, "a b c")
    }

    func testEmptyHiddenIsIdentity() {
        let s = NSAttributedString(string: "no markers")
        XCTAssertEqual(MarkupCollapse.collapsed(s, hiding: []).string, "no markers")
    }

    func testPreservesAttributesOnSurvivingText() {
        let s = NSMutableAttributedString(string: "**X**")
        s.addAttribute(.foregroundColor, value: NSObject(), range: NSRange(location: 2, length: 1)) // on "X"
        let out = MarkupCollapse.collapsed(s, hiding: [
            NSRange(location: 0, length: 2),
            NSRange(location: 3, length: 2),
        ])
        XCTAssertEqual(out.string, "X")
        XCTAssertNotNil(out.attribute(.foregroundColor, at: 0, effectiveRange: nil))
    }
}
