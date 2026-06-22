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
        case image
        /// `<https://…>` / `<a@b.c>` style autolink.
        case autolink
        case blockQuote
        case listItem(ordered: Bool)
        case taskItem(checked: Bool)
        case thematicBreak
        /// A GFM `> [!NOTE]` callout/admonition; `kind` is the uppercased label (NOTE, TIP, WARNING…).
        case callout(kind: String)
        /// A GFM pipe table (the whole `| … |` block).
        case table
        /// YAML (`---`) or TOML (`+++`) document frontmatter.
        case frontmatter
        /// `$…$` (inline) or `$$…$$` (display) LaTeX math.
        case math(display: Bool)
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
    /// For `.link` / `.image` / `.autolink`: the raw destination string (URL, relative path, or
    /// `[[wiki]]` target). Carried as a parallel field rather than a `Role` associated value so it
    /// doesn't ripple through every exhaustive `Role` switch in the styler/exporters. `nil` otherwise.
    public let linkDestination: String?
    /// For `.taskItem`: the exact range of the `[ ]` / `[x]` literal, so F2 click-to-toggle can
    /// rewrite it unambiguously without inferring which `markerRange` is the checkbox. `nil` otherwise.
    public let checkboxRange: NSRange?

    public init(role: Role,
                nodeRange: NSRange,
                contentRange: NSRange,
                markerRanges: [NSRange],
                linkDestination: String? = nil,
                checkboxRange: NSRange? = nil) {
        self.role = role
        self.nodeRange = nodeRange
        self.contentRange = contentRange
        self.markerRanges = markerRanges
        self.linkDestination = linkDestination
        self.checkboxRange = checkboxRange
    }
}
