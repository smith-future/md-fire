import Foundation
import SwiftTreeSitter
import TreeSitterMarkdown
import TreeSitterMarkdownInline

/// The primary parser. Uses the tree-sitter split markdown grammars (block + inline) to produce
/// `SyntaxNode`s with precise content vs marker ranges. Block structure is parsed once; each
/// `inline` leaf is then parsed with the inline grammar and rebased onto the document.
///
/// IMPORTANT: SwiftTreeSitter's `Parser.parse(_ String)` feeds the bytes as UTF-16LE
/// (`TSInputEncodingUTF16LE`, see SwiftTreeSitter/Parser.swift), so tree-sitter byte offsets are in
/// **UTF-16 bytes** — exactly two per code unit. Dividing by two yields UTF-16 code-unit offsets,
/// which is precisely what `NSRange` / NSTextStorage use. So we work in UTF-16 throughout and need no
/// UTF-8↔UTF-16 conversion here (RangeMapping remains for the cmark/export path, whose source
/// locations are UTF-8 based).
///
/// Phase 1 is a full parse on demand. Incremental `Tree.edit()` reuse is layered on in Phase 2.
public final class TreeSitterParser {
    private let blockParser = Parser()
    private let inlineParser = Parser()

    public init() {
        // A statically linked grammar always loads; failure would be a build/linker bug, not runtime.
        try! blockParser.setLanguage(Language(language: tree_sitter_markdown()))
        try! inlineParser.setLanguage(Language(language: tree_sitter_markdown_inline()))
    }

    public func parse(_ source: String) -> [SyntaxNode] {
        let nsSource = source as NSString
        guard let tree = blockParser.parse(source), let root = tree.rootNode else { return [] }
        var out: [SyntaxNode] = []
        walkBlock(root, nsSource: nsSource, into: &out)
        return out
    }

    // MARK: - Range helpers (UTF-16 bytes -> code units)

    private func loc(_ node: Node) -> Int { Int(node.byteRange.lowerBound) / 2 }
    private func end(_ node: Node) -> Int { Int(node.byteRange.upperBound) / 2 }
    private func range(_ node: Node) -> NSRange { NSRange(location: loc(node), length: end(node) - loc(node)) }
    private func shifted(_ node: Node, by offset: Int) -> NSRange {
        NSRange(location: offset + loc(node), length: end(node) - loc(node))
    }

    private func children(_ node: Node) -> [Node] {
        (0..<node.childCount).compactMap { node.child(at: $0) }
    }

    private func headingLevel(_ type: String) -> Int? {
        guard type.hasPrefix("atx_h"), type.hasSuffix("_marker") else { return nil }
        return Int(type.drop { !$0.isNumber }.prefix { $0.isNumber })
    }

    // MARK: - Block walk

    private func walkBlock(_ node: Node, nsSource: NSString, into out: inout [SyntaxNode]) {
        switch node.nodeType ?? "" {
        case "atx_heading":
            let kids = children(node)
            let markerNode = kids.first { headingLevel($0.nodeType ?? "") != nil }
            let contentNode = kids.first { $0.nodeType == "inline" }
            let level = markerNode.flatMap { headingLevel($0.nodeType ?? "") } ?? 1
            out.append(SyntaxNode(
                role: .heading(level: level),
                nodeRange: range(node),
                contentRange: contentNode.map { range($0) } ?? range(node),
                markerRanges: markerNode.map { [range($0)] } ?? []
            ))
            if let c = contentNode { parseInline(c, nsSource: nsSource, into: &out) }

        case "paragraph":
            out.append(SyntaxNode(role: .paragraph, nodeRange: range(node),
                                  contentRange: range(node), markerRanges: []))
            for c in children(node) where c.nodeType == "inline" {
                parseInline(c, nsSource: nsSource, into: &out)
            }

        case "block_quote":
            let kids = children(node)
            let markers = kids.filter { $0.nodeType == "block_quote_marker" }.map { range($0) }
            out.append(SyntaxNode(role: .blockQuote, nodeRange: range(node),
                                  contentRange: range(node), markerRanges: markers))
            for c in kids { walkBlock(c, nsSource: nsSource, into: &out) }

        case "list_item":
            emitListItem(node, nsSource: nsSource, into: &out)

        case "fenced_code_block":
            emitFencedCode(node, nsSource: nsSource, into: &out)

        case "thematic_break":
            let r = range(node)
            out.append(SyntaxNode(role: .thematicBreak, nodeRange: r,
                                  contentRange: NSRange(location: r.location, length: 0),
                                  markerRanges: [r]))

        default:
            for c in children(node) { walkBlock(c, nsSource: nsSource, into: &out) }
        }
    }

    private func emitListItem(_ node: Node, nsSource: NSString, into out: inout [SyntaxNode]) {
        let kids = children(node)
        let listMarkers = kids.filter { ($0.nodeType ?? "").hasPrefix("list_marker_") }
        let unchecked = kids.first { $0.nodeType == "task_list_marker_unchecked" }
        let checked = kids.first { $0.nodeType == "task_list_marker_checked" }
        var markers = listMarkers.map { range($0) }
        if let task = checked ?? unchecked { markers.append(range(task)) }
        let ordered = listMarkers.contains {
            $0.nodeType == "list_marker_dot" || $0.nodeType == "list_marker_parenthesis"
        }
        let role: SyntaxNode.Role
        if checked != nil { role = .taskItem(checked: true) }
        else if unchecked != nil { role = .taskItem(checked: false) }
        else { role = .listItem(ordered: ordered) }
        out.append(SyntaxNode(role: role, nodeRange: range(node),
                              contentRange: range(node), markerRanges: markers))
        for c in kids { walkBlock(c, nsSource: nsSource, into: &out) }
    }

    private func emitFencedCode(_ node: Node, nsSource: NSString, into out: inout [SyntaxNode]) {
        let kids = children(node)
        var markers = kids.filter { $0.nodeType == "fenced_code_block_delimiter" }.map { range($0) }
        let infoNode = kids.first { $0.nodeType == "info_string" }
        if let info = infoNode { markers.append(range(info)) }
        let langNode = infoNode.flatMap { children($0).first { $0.nodeType == "language" } }
        let language = langNode.map { nsSource.substring(with: range($0)) }
        let contentNode = kids.first { $0.nodeType == "code_fence_content" }
        out.append(SyntaxNode(
            role: .codeBlock(language: language),
            nodeRange: range(node),
            contentRange: contentNode.map { range($0) } ?? range(node),
            markerRanges: markers
        ))
    }

    // MARK: - Inline second pass

    private func parseInline(_ inlineNode: Node, nsSource: NSString, into out: inout [SyntaxNode]) {
        let docRange = range(inlineNode)
        guard docRange.length > 0, NSMaxRange(docRange) <= nsSource.length else { return }
        let sub = nsSource.substring(with: docRange)
        guard let tree = inlineParser.parse(sub), let root = tree.rootNode else { return }
        walkInline(root, docOffset: docRange.location, into: &out)
    }

    private func walkInline(_ node: Node, docOffset: Int, into out: inout [SyntaxNode]) {
        let type = node.nodeType ?? ""
        switch type {
        case "emphasis", "strong_emphasis", "strikethrough":
            let kids = children(node)
            let delims = kids.filter { $0.nodeType == "emphasis_delimiter" }.sorted { loc($0) < loc($1) }
            let role: SyntaxNode.Role = type == "emphasis" ? .emphasis
                : type == "strong_emphasis" ? .strong : .strikethrough
            let contentRange: NSRange
            let half = delims.count / 2
            if half >= 1 {
                let s = docOffset + end(delims[half - 1])
                let e = docOffset + loc(delims[half])
                contentRange = NSRange(location: s, length: max(0, e - s))
            } else {
                contentRange = shifted(node, by: docOffset)
            }
            out.append(SyntaxNode(
                role: role,
                nodeRange: shifted(node, by: docOffset),
                contentRange: contentRange,
                markerRanges: delims.map { shifted($0, by: docOffset) }
            ))
            for c in kids where ["emphasis", "strong_emphasis", "strikethrough", "code_span", "inline_link"].contains(c.nodeType ?? "") {
                walkInline(c, docOffset: docOffset, into: &out)
            }

        case "code_span":
            let delims = children(node).filter { $0.nodeType == "code_span_delimiter" }.sorted { loc($0) < loc($1) }
            let s = delims.first.map { docOffset + end($0) } ?? (docOffset + loc(node))
            let e = delims.last.map { docOffset + loc($0) } ?? (docOffset + end(node))
            out.append(SyntaxNode(
                role: .codeSpan,
                nodeRange: shifted(node, by: docOffset),
                contentRange: NSRange(location: s, length: max(0, e - s)),
                markerRanges: delims.map { shifted($0, by: docOffset) }
            ))

        case "inline_link":
            let textNode = children(node).first { $0.nodeType == "link_text" }
            let full = shifted(node, by: docOffset)
            let content = textNode.map { shifted($0, by: docOffset) } ?? full
            var markers: [NSRange] = []
            let leftLen = content.location - full.location
            if leftLen > 0 { markers.append(NSRange(location: full.location, length: leftLen)) }
            let rightStart = content.location + content.length
            let rightLen = (full.location + full.length) - rightStart
            if rightLen > 0 { markers.append(NSRange(location: rightStart, length: rightLen)) }
            out.append(SyntaxNode(role: .link, nodeRange: full, contentRange: content, markerRanges: markers))

        default:
            for c in children(node) { walkInline(c, docOffset: docOffset, into: &out) }
        }
    }
}
