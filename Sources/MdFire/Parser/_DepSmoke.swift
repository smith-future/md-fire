import Foundation
import SwiftTreeSitter
import TreeSitterMarkdown
import TreeSitterMarkdownInline
import Markdown

/// TEMPORARY Phase-1 link smoke test. Proves the tree-sitter split grammars and
/// swift-markdown resolve, compile, and link in this Xcode toolchain.
/// Deleted once TreeSitterParser.swift + tests exist.
enum _DepSmoke {
    static func describe() -> String {
        let block = Language(language: tree_sitter_markdown())
        let inline = Language(language: tree_sitter_markdown_inline())
        let doc = Document(parsing: "# Hello\n\n**bold** _em_ `code`")
        return "ts-block fields=\(block.fieldCount) ts-inline fields=\(inline.fieldCount) cmark children=\(doc.childCount)"
    }
}
