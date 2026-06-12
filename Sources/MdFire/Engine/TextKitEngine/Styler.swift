import AppKit
import STTextView
import MarkdownCore

/// Applies a `StylePolicy`'s attributes over already-parsed nodes. Identical for both editing
/// models — it just asks the policy for content + marker attributes and writes them. The Coordinator
/// parses once and shares the nodes with both the Styler and the MarkupHider.
struct Styler {
    /// `revealLocation` is the caret offset (or nil). In WYSIWYG mode, the element containing the
    /// caret shows its markers (reveal) instead of collapsing them.
    func apply(to textView: STTextView, nodes: [SyntaxNode], policy: StylePolicy, theme: Theme,
               revealLocation: Int? = nil) {
        let nsLen = (textView.text as NSString?)?.length ?? 0
        guard nsLen > 0 else { return }
        let full = NSRange(location: 0, length: nsLen)

        // Base layer: body font/color + line height across the whole document.
        textView.addAttributes([
            .font: theme.bodyFont,
            .foregroundColor: theme.palette.body,
            .paragraphStyle: theme.paragraphStyle(),
        ], range: full)

        // Per-node: content first, then markers (so marker styling wins on its own ranges).
        for node in nodes {
            let content = policy.contentAttributes(for: node, theme: theme)
            if !content.isEmpty, isValid(node.contentRange, nsLen) {
                textView.addAttributes(content, range: node.contentRange)
            }
            guard !node.markerRanges.isEmpty else { continue }
            let revealed = policy.revealsAtCaret
                && revealLocation.map { caretInside($0, node.nodeRange) } == true
            let marker = revealed
                ? policy.revealedMarkerAttributes(for: node, theme: theme)
                : policy.markerAttributes(for: node, theme: theme)
            for range in node.markerRanges where isValid(range, nsLen) {
                textView.addAttributes(marker, range: range)
            }
        }
    }

    /// Caret counts as "inside" when it sits anywhere within the element, including either edge,
    /// so markers reveal as the caret arrives at and traverses the construct.
    private func caretInside(_ location: Int, _ range: NSRange) -> Bool {
        location >= range.location && location <= range.location + range.length
    }

    private func isValid(_ r: NSRange, _ length: Int) -> Bool {
        r.location != NSNotFound && r.location >= 0 && r.length >= 0 && r.location + r.length <= length
    }
}
