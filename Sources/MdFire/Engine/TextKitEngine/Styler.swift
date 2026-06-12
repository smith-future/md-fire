import AppKit
import STTextView
import MarkdownCore

/// Applies a `StylePolicy`'s attributes over the parsed nodes. Identical for both editing models —
/// it just asks the policy for content + marker attributes and writes them. This is the single point
/// where parse output becomes presentation; switching mode = swap the policy and re-run.
struct Styler {
    private let parser = TreeSitterParser()

    func apply(to textView: STTextView, source: String, policy: StylePolicy, theme: Theme) {
        let nsLen = (source as NSString).length
        guard nsLen > 0 else { return }
        let full = NSRange(location: 0, length: nsLen)

        // Base layer: body font/color + line height across the whole document.
        textView.addAttributes([
            .font: theme.bodyFont,
            .foregroundColor: theme.palette.body,
            .paragraphStyle: theme.paragraphStyle(),
        ], range: full)

        // Per-node: content first, then markers (so marker styling wins on its own ranges).
        for node in parser.parse(source) {
            let content = policy.contentAttributes(for: node, theme: theme)
            if !content.isEmpty, isValid(node.contentRange, nsLen) {
                textView.addAttributes(content, range: node.contentRange)
            }
            guard !node.markerRanges.isEmpty else { continue }
            let marker = policy.markerAttributes(for: node, theme: theme)
            for range in node.markerRanges where isValid(range, nsLen) {
                textView.addAttributes(marker, range: range)
            }
        }
    }

    private func isValid(_ r: NSRange, _ length: Int) -> Bool {
        r.location != NSNotFound && r.location >= 0 && r.length >= 0 && r.location + r.length <= length
    }
}
