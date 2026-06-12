import Foundation

/// A markdown construct with precise UTF-16 ranges, split into the rendered **content** and the
/// raw **markers** (delimiters/punctuation). This split is the heart of the dual-mode engine:
/// - WYSIWYG mode hides `markerRanges` and styles `contentRange`.
/// - Syntax-visible mode dims `markerRanges` and styles `contentRange`.
/// The same `SyntaxNode` drives both — see ARCHITECTURE.md §4.
public struct SyntaxNode: Equatable {
    public enum Role: Equatable {
        case heading(level: Int)
        case paragraph
        case emphasis
        case strong
        case strikethrough
        case codeSpan
        case codeBlock(language: String?)
        case link
        case blockQuote
        case listItem(ordered: Bool)
        case taskItem(checked: Bool)
        case thematicBreak
        case text
    }

    public let role: Role
    /// Full span of the construct, markers + content.
    public let nodeRange: NSRange
    /// The rendered-text portion (what the reader sees formatted).
    public let contentRange: NSRange
    /// Delimiter / marker runs: `#`, `*`, `_`, `` ` ``, `~`, `>`, list bullets, fences.
    /// Hidden in WYSIWYG mode, dimmed in syntax-visible mode.
    public let markerRanges: [NSRange]

    public init(role: Role, nodeRange: NSRange, contentRange: NSRange, markerRanges: [NSRange]) {
        self.role = role
        self.nodeRange = nodeRange
        self.contentRange = contentRange
        self.markerRanges = markerRanges
    }
}
