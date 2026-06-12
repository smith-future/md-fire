import Foundation
import Markdown

/// Secondary parser: Apple's swift-markdown (cmark-gfm). Two jobs:
/// 1. Export path (Phase 7) — a conformant AST to render themed HTML.
/// 2. Test oracle — independent block-structure counts to cross-check the tree-sitter parser.
public struct CmarkExportParser {
    public init() {}

    public struct BlockStats: Equatable {
        public let headings: Int
        public let listItems: Int
        public let codeBlocks: Int
        public let blockQuotes: Int
    }

    public func blockStats(_ source: String) -> BlockStats {
        let doc = Document(parsing: source)
        return BlockStats(
            headings: count(doc) { $0 is Heading },
            listItems: count(doc) { $0 is ListItem },
            codeBlocks: count(doc) { $0 is CodeBlock },
            blockQuotes: count(doc) { $0 is BlockQuote }
        )
    }

    private func count(_ markup: Markup, where predicate: (Markup) -> Bool) -> Int {
        var total = predicate(markup) ? 1 : 0
        for child in markup.children { total += count(child, where: predicate) }
        return total
    }
}
