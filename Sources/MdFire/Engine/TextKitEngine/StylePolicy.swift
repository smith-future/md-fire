import AppKit
import MarkdownCore

public extension NSAttributedString.Key {
    /// Marks a marker run that should be hidden from layout (consumed by the custom layout fragment
    /// in Stage 2). Present in WYSIWYG mode; absent in syntax-visible mode.
    static let mdHiddenMarker = NSAttributedString.Key("mdHiddenMarker")
}

/// The ONLY thing that differs between the two editing models. Content styling is shared; the
/// policies differ purely in how markers are presented and whether markers reveal at the caret.
public protocol StylePolicy {
    var hidesMarkup: Bool { get }
    var revealsAtCaret: Bool { get }
    func contentAttributes(for node: SyntaxNode, theme: Theme) -> [NSAttributedString.Key: Any]
    func markerAttributes(for node: SyntaxNode, theme: Theme) -> [NSAttributedString.Key: Any]
    /// How a marker looks when the caret is inside its element (WYSIWYG reveal). Restores full size +
    /// dim color so hidden markers become editable, then collapse again when the caret leaves.
    func revealedMarkerAttributes(for node: SyntaxNode, theme: Theme) -> [NSAttributedString.Key: Any]
}

public extension StylePolicy {
    /// Shared across both modes: how the *rendered text* of each construct looks.
    func contentAttributes(for node: SyntaxNode, theme: Theme) -> [NSAttributedString.Key: Any] {
        switch node.role {
        case .heading(let level):
            return [.font: theme.font(size: theme.headingSize(level), bold: true),
                    .foregroundColor: theme.palette.body]
        case .strong:
            return [.font: theme.font(size: theme.baseSize, bold: true)]
        case .emphasis:
            return [.font: theme.font(size: theme.baseSize, italic: true)]
        case .strikethrough:
            return [.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: theme.palette.dimmed]
        case .codeSpan, .codeBlock:
            return [.font: theme.font(size: theme.baseSize * 0.95),
                    .backgroundColor: theme.palette.codeBg]
        case .link:
            return [.foregroundColor: theme.palette.accent,
                    .underlineStyle: NSUnderlineStyle.single.rawValue]
        case .blockQuote:
            return [.foregroundColor: theme.palette.dimmed,
                    .font: theme.font(size: theme.baseSize, italic: true)]
        case .paragraph, .listItem, .taskItem, .text, .thematicBreak:
            return [:]
        }
    }

    /// Default reveal: full-size, dim markers (same look as syntax-visible mode).
    func revealedMarkerAttributes(for node: SyntaxNode, theme: Theme) -> [NSAttributedString.Key: Any] {
        [.font: theme.bodyFont, .foregroundColor: theme.palette.marker]
    }
}

/// iA Writer model: markers stay visible, dimmed. Honest source.
public struct SyntaxVisiblePolicy: StylePolicy {
    public init() {}
    public let hidesMarkup = false
    public let revealsAtCaret = false
    public func markerAttributes(for node: SyntaxNode, theme: Theme) -> [NSAttributedString.Key: Any] {
        [.foregroundColor: theme.palette.marker]
    }
}

/// Typora model: markers are collapsed by shrinking them to a near-zero-width, transparent glyph —
/// an attribute-only approach that keeps the storage length intact (so STTextView's TextKit-2 layout
/// and selection math stay consistent, unlike content-string substitution which breaks it). The
/// characters remain in the backing store; `.mdHiddenMarker` tags them for caret-reveal + atomic
/// handling (next step). When revealed at the caret they'll be restored to the dim marker style.
public struct LiveWYSIWYGPolicy: StylePolicy {
    public init() {}
    public let hidesMarkup = true
    public let revealsAtCaret = true
    public func markerAttributes(for node: SyntaxNode, theme: Theme) -> [NSAttributedString.Key: Any] {
        switch node.role {
        case .heading, .strong, .emphasis, .codeSpan, .strikethrough, .link:
            // Collapse to a near-zero-width transparent glyph (storage length intact).
            return [.font: theme.font(size: 0.01), .foregroundColor: NSColor.clear, .mdHiddenMarker: true]
        default:
            // List bullets, task checkboxes, blockquote bars, code fences — Typora keeps these
            // as styled glyphs, so render them dimmed rather than hiding them.
            return [.foregroundColor: theme.palette.marker]
        }
    }
}
