import XCTest
@testable import MarkdownCore

final class FocusRangeTests: XCTestCase {

    private func sub(_ s: String, _ r: NSRange) -> String { (s as NSString).substring(with: r) }

    func testOffReturnsNil() {
        XCTAssertNil(FocusRange.active(in: "hello world", caret: 3, scope: .off))
    }

    func testParagraphRange() {
        let text = "First paragraph.\n\nSecond paragraph here.\n"
        // caret inside the second paragraph
        let caret = (text as NSString).range(of: "Second").location + 2
        let r = FocusRange.active(in: text, caret: caret, scope: .paragraph)
        XCTAssertNotNil(r)
        XCTAssertTrue(sub(text, r!).contains("Second paragraph here."))
        XCTAssertFalse(sub(text, r!).contains("First"))
    }

    func testSentenceRange() {
        let text = "One sentence here. Second sentence follows. Third one."
        let caret = (text as NSString).range(of: "Second").location + 1
        let r = FocusRange.active(in: text, caret: caret, scope: .sentence)
        XCTAssertNotNil(r)
        let s = sub(text, r!)
        XCTAssertTrue(s.contains("Second sentence follows."))
        XCTAssertFalse(s.contains("One sentence here."))
        XCTAssertFalse(s.contains("Third one."))
    }

    func testEmptyText() {
        XCTAssertNil(FocusRange.active(in: "", caret: 0, scope: .paragraph))
    }

    func testCaretClampedOutOfBounds() {
        let text = "Just one paragraph."
        let r = FocusRange.active(in: text, caret: 9999, scope: .paragraph)
        XCTAssertNotNil(r)
        XCTAssertEqual(sub(text, r!), "Just one paragraph.")
    }
}
