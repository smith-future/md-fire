import Foundation

/// Pure core of WYSIWYG marker hiding: remove the hidden ranges from an attributed string. Used by
/// the TextKit 2 content-storage delegate to collapse markers out of the *display* string while the
/// backing storage keeps the full Markdown. Kept here (not in the AppKit engine) so it is unit-testable.
public enum MarkupCollapse {
    /// `source` with every `hidden` range deleted. Ranges are clamped and applied back-to-front so
    /// earlier offsets stay valid. Overlapping/adjacent ranges are handled by the clamp.
    public static func collapsed(_ source: NSAttributedString, hiding hidden: [NSRange]) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        let full = NSRange(location: 0, length: result.length)
        for range in hidden.sorted(by: { $0.location > $1.location }) {
            let clamped = NSIntersectionRange(range, full)
            if clamped.length > 0 { result.deleteCharacters(in: clamped) }
        }
        return result
    }
}
