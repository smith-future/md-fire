import XCTest
@testable import MarkdownCore

/// Coverage for the node-type detection layer added for the vibe-coding-cockpit (F2/F3/F4):
/// task checkbox ranges, link/image destinations, autolinks, tables, frontmatter, callouts, math,
/// and the wiki-link regex fallback. Cross-checked against the swift-markdown (cmark) oracle.
final class NodeDetectionTests: XCTestCase {

    private func sub(_ source: String, _ range: NSRange) -> String {
        (source as NSString).substring(with: range)
    }
    private func first(_ nodes: [SyntaxNode], _ match: (SyntaxNode.Role) -> Bool) -> SyntaxNode? {
        nodes.first { match($0.role) }
    }

    // MARK: F2 — explicit checkbox range

    func testCheckboxRange() {
        let src = "- [ ] todo\n- [x] done\n"
        let nodes = TreeSitterParser().parse(src)
        guard let todo = first(nodes, { if case .taskItem(false) = $0 { return true }; return false }),
              let done = first(nodes, { if case .taskItem(true) = $0 { return true }; return false }) else {
            return XCTFail("missing task items")
        }
        XCTAssertEqual(todo.checkboxRange.map { sub(src, $0) }, "[ ]")
        XCTAssertEqual(done.checkboxRange.map { sub(src, $0) }, "[x]")
        // The checkbox is NOT hidden as a marker any more (F2 needs it visible/clickable).
        XCTAssertFalse(todo.markerRanges.contains { sub(src, $0) == "[ ]" })
    }

    // MARK: F4 — link / image destinations + autolinks

    func testLinkDestination() {
        let src = "see [the docs](./ARCHITECTURE.md) here\n"
        let nodes = TreeSitterParser().parse(src)
        guard let link = first(nodes, { if case .link = $0 { return true }; return false }) else {
            return XCTFail("no link node")
        }
        XCTAssertEqual(sub(src, link.contentRange), "the docs")
        XCTAssertEqual(link.linkDestination, "./ARCHITECTURE.md")
    }

    func testImageDestination() {
        let src = "![alt text](img.png)\n"
        let nodes = TreeSitterParser().parse(src)
        guard let img = first(nodes, { if case .image = $0 { return true }; return false }) else {
            return XCTFail("no image node")
        }
        XCTAssertEqual(sub(src, img.contentRange), "alt text")
        XCTAssertEqual(img.linkDestination, "img.png")
    }

    func testAutolink() {
        let src = "visit <https://example.com> now\n"
        let nodes = TreeSitterParser().parse(src)
        guard let a = first(nodes, { if case .autolink = $0 { return true }; return false }) else {
            return XCTFail("no autolink node")
        }
        XCTAssertEqual(sub(src, a.contentRange), "https://example.com")
        XCTAssertEqual(a.linkDestination, "https://example.com")
    }

    // MARK: F3 — table

    func testTable() {
        let src = "| a | b |\n|---|---|\n| 1 | 2 |\n"
        let nodes = TreeSitterParser().parse(src)
        let tables = nodes.filter { if case .table = $0.role { return true }; return false }
        XCTAssertEqual(tables.count, 1)
        XCTAssertEqual(tables.count, CmarkExportParser().blockStats(src).tables, "table count vs cmark oracle")
        XCTAssertEqual(sub(src, tables[0].nodeRange).contains("| 1 | 2 |"), true)
    }

    func testTableCellInlineStyled() {
        let src = "| **bold** | x |\n|---|---|\n| a | b |\n"
        let nodes = TreeSitterParser().parse(src)
        // The strong inside the header cell still gets an inline node.
        let strong = first(nodes, { if case .strong = $0 { return true }; return false })
        XCTAssertEqual(strong.map { sub(src, $0.contentRange) }, "bold")
    }

    // MARK: F3 — frontmatter

    func testFrontmatterYAML() {
        let src = "---\ntitle: Hi\ntag: x\n---\n\n# Body\n"
        let nodes = TreeSitterParser().parse(src)
        let fm = first(nodes, { if case .frontmatter = $0 { return true }; return false })
        XCTAssertNotNil(fm, "expected a frontmatter node")
        XCTAssertEqual(fm.map { sub(src, $0.nodeRange).hasPrefix("---") }, true)
        // The heading after the frontmatter is still detected normally.
        XCTAssertNotNil(first(nodes, { if case .heading = $0 { return true }; return false }))
    }

    func testFrontmatterTOML() {
        let src = "+++\ntitle = \"Hi\"\n+++\n\nbody\n"
        let nodes = TreeSitterParser().parse(src)
        XCTAssertNotNil(first(nodes, { if case .frontmatter = $0 { return true }; return false }))
    }

    // MARK: F3 — callouts

    func testCallout() {
        let src = "> [!NOTE]\n> body of note\n"
        let nodes = TreeSitterParser().parse(src)
        let callout = first(nodes, { if case .callout = $0 { return true }; return false })
        guard case .callout(let kind)? = callout?.role else { return XCTFail("no callout node") }
        XCTAssertEqual(kind, "NOTE")
    }

    func testPlainBlockQuoteIsNotCallout() {
        let src = "> just a quote\n"
        let nodes = TreeSitterParser().parse(src)
        XCTAssertNotNil(first(nodes, { if case .blockQuote = $0 { return true }; return false }))
        XCTAssertNil(first(nodes, { if case .callout = $0 { return true }; return false }))
    }

    // MARK: F3 — math

    func testInlineMath() {
        let src = "inline $x^2$ here\n"
        let nodes = TreeSitterParser().parse(src)
        guard let m = first(nodes, { if case .math = $0 { return true }; return false }) else {
            return XCTFail("no math node")
        }
        if case .math(let display) = m.role { XCTAssertFalse(display) }
        XCTAssertEqual(sub(src, m.contentRange), "x^2")
    }

    func testDisplayMath() {
        let src = "$$\na=b\n$$\n"
        let nodes = TreeSitterParser().parse(src)
        guard let m = first(nodes, { if case .math = $0 { return true }; return false }) else {
            return XCTFail("no display math node")
        }
        if case .math(let display) = m.role { XCTAssertTrue(display) }
    }

    // MARK: F4 — wiki-link fallback

    func testWikiLinkSimple() {
        let src = "see [[Some Page]] now\n"
        let nodes = TreeSitterParser().parse(src)
        guard let w = first(nodes, { if case .link = $0 { return true }; return false }) else {
            return XCTFail("no wiki link node")
        }
        XCTAssertEqual(w.linkDestination, "Some Page")
        XCTAssertEqual(sub(src, w.contentRange), "Some Page")
    }

    func testWikiLinkWithAlias() {
        let src = "see [[md-fire-project|the project]] now\n"
        let nodes = TreeSitterParser().parse(src)
        guard let w = first(nodes, { if case .link = $0 { return true }; return false }) else {
            return XCTFail("no wiki link node")
        }
        XCTAssertEqual(w.linkDestination, "md-fire-project")
        XCTAssertEqual(sub(src, w.contentRange), "the project")
    }

    func testWikiLinkInsideCodeIsIgnored() {
        let src = "`[[not a link]]` and [[Real]]\n"
        let nodes = TreeSitterParser().parse(src)
        let wikis = nodes.filter { if case .link = $0.role { return true }; return false }
        XCTAssertEqual(wikis.count, 1, "only the one outside the code span counts")
        XCTAssertEqual(wikis.first?.linkDestination, "Real")
    }
}
