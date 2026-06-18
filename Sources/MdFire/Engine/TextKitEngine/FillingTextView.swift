import AppKit
import STTextView

/// An STTextView that never shrinks below its scroll view's visible height. By default STTextView
/// sizes itself to its content, so the empty area below a short document isn't part of the text view
/// and clicks there do nothing. Filling the viewport makes clicking anywhere below the text place the
/// caret at the end of the document — the Obsidian-style "click in the void and start writing".
final class FillingTextView: STTextView {
    override func setFrameSize(_ newSize: NSSize) {
        var size = newSize
        if let clipHeight = enclosingScrollView?.contentView.bounds.height, clipHeight > 0 {
            size.height = max(size.height, clipHeight)
        }
        super.setFrameSize(size)
    }
}
