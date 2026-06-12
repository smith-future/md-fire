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

/// Typora model: markers hidden (here via background-blend as a Stage-1 preview; true layout
/// collapse + caret reveal + atomic ranges land in Phase 2.3). `.mdHiddenMarker` tags the runs.
public struct LiveWYSIWYGPolicy: StylePolicy {
    public init() {}
    public let hidesMarkup = true
    public let revealsAtCaret = true
    public func markerAttributes(for node: SyntaxNode, theme: Theme) -> [NSAttributedString.Key: Any] {
        [.foregroundColor: theme.palette.bg, .mdHiddenMarker: true]
    }
}
