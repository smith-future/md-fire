import XCTest
@testable import MarkdownCore

final class ParserTests: XCTestCase {

    private func sub(_ source: String, _ range: NSRange) -> String {
        (source as NSString).substring(with: range)
    }

    private func first(_ nodes: [SyntaxNode], _ match: (SyntaxNode.Role) -> Bool) -> SyntaxNode? {
        nodes.first { match($0.role) }
    }

    // MARK: heading

    func testHeadingMarkerAndContent() {
        let src = "# Heading one\n"
        let nodes = TreeSitterParser().parse(src)
        guard let h = first(nodes, { if case .heading = $0 { return true }; return false }) else {
            return XCTFail("no heading node")
        }
        if case .heading(let level) = h.role { XCTAssertEqual(level, 1) }
        XCTAssertEqual(h.markerRanges.count, 1)
        XCTAssertEqual(sub(src, h.markerRanges[0]), "#")
        XCTAssertEqual(sub(src, h.contentRange), "Heading one")
    }

    func testHeadingLevels() {
        for level in 1...6 {
            let hashes = String(repeating: "#", count: level)
            let src = "\(hashes) Title\n"
            let nodes = TreeSitterParser().parse(src)
            guard let h = first(nodes, { if case .heading = $0 { return true }; return false }) else {
                return XCTFail("no heading for level \(level)")
            }
            if case .heading(let parsed) = h.role { XCTAssertEqual(parsed, level) }
            XCTAssertEqual(sub(src, h.markerRanges[0]), hashes)
            XCTAssertEqual(sub(src, h.contentRange), "Title")
        }
    }

    // MARK: inline bold / em / code — the BUILD-PLAN Phase 1 assertion

    func testBoldEmphasisCodeRanges() {
        let src = "x **bold** _em_ `code`\n"
        let nodes = TreeSitterParser().parse(src)

        guard let strong = first(nodes, { if case .strong = $0 { return true }; return false }) else {
            return XCTFail("no strong node")
        }
        XCTAssertEqual(sub(src, strong.contentRange), "bold")
        // 4 single-'*' delimiter markers that together form "**" + "**".
        XCTAssertEqual(strong.markerRanges.map { sub(src, $0) }.joined(), "****")

        guard let em = first(nodes, { if case .emphasis = $0 { return true }; return false }) else {
            return XCTFail("no emphasis node")
        }
        XCTAssertEqual(sub(src, em.contentRange), "em")
        XCTAssertEqual(em.markerRanges.map { sub(src, $0) }.joined(), "__")

        guard let code = first(nodes, { if case .codeSpan = $0 { return true }; return false }) else {
            return XCTFail("no codeSpan node")
        }
        XCTAssertEqual(sub(src, code.contentRange), "code")
        XCTAssertEqual(code.markerRanges.map { sub(src, $0) }.joined(), "``")
    }

    // MARK: ranges stay correct across multibyte content

    func testMultibyteInlineRanges() {
        let src = "**жирный** текст\n"   // Cyrillic inside bold
        let nodes = TreeSitterParser().parse(src)
        guard let strong = first(nodes, { if case .strong = $0 { return true }; return false }) else {
            return XCTFail("no strong node")
        }
        XCTAssertEqual(sub(src, strong.contentRange), "жирный")
    }

    func testEmojiOffsetsDoNotCorrupt() {
        let src = "# 😀 `x`\n"
        let nodes = TreeSitterParser().parse(src)
        guard let code = first(nodes, { if case .codeSpan = $0 { return true }; return false }) else {
            return XCTFail("no codeSpan node")
        }
        XCTAssertEqual(sub(src, code.contentRange), "x")
    }

    // MARK: block-structure oracle cross-check (tree-sitter vs cmark-gfm)

    func testHeadingCountMatchesCmark() {
        let src = "# A\n\n## B\n\nsome text\n\n### C\n"
        let mine = TreeSitterParser().parse(src)
            .filter { if case .heading = $0.role { return true }; return false }.count
        let oracle = CmarkExportParser().blockStats(src).headings
        XCTAssertEqual(mine, oracle)
        XCTAssertEqual(mine, 3)
    }

    func testTaskItems() {
        let src = "- [ ] todo\n- [x] done\n"
        let nodes = TreeSitterParser().parse(src)
        let unchecked = first(nodes, { if case .taskItem(false) = $0 { return true }; return false })
        let checked = first(nodes, { if case .taskItem(true) = $0 { return true }; return false })
        XCTAssertNotNil(unchecked, "expected an unchecked task item")
        XCTAssertNotNil(checked, "expected a checked task item")
    }
}
