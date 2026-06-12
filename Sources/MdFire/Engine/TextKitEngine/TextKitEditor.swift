import SwiftUI
import AppKit
import STTextView
import MarkdownCore

/// SwiftUI host for the TextKit 2 editor (STTextView). Phase 2: renders a document in either editing
/// model via one pipeline. The Coordinator parses once and shares the nodes between the Styler
/// (attributes) and the MarkupHider (WYSIWYG marker collapse via the content-storage delegate).
struct TextKitEditor: NSViewRepresentable {
    let text: String
    let mode: RenderMode
    var theme: Theme = .light

    func makeCoordinator() -> Coordinator { Coordinator(mode: mode, theme: theme) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = STTextView.scrollableTextView()
        // swiftlint:disable:next force_cast
        let textView = scrollView.documentView as! STTextView
        let coordinator = context.coordinator
        coordinator.textView = textView

        textView.textDelegate = coordinator
        textView.isHorizontallyResizable = false   // wrap to the view width
        textView.font = theme.bodyFont
        textView.textColor = theme.palette.body
        textView.backgroundColor = theme.palette.bg
        textView.insertionPointColor = theme.palette.accent
        textView.textContainer.lineFragmentPadding = 28
        scrollView.backgroundColor = theme.palette.bg
        scrollView.drawsBackground = true

        // NOTE: content-storage display substitution (returning shorter paragraphs from
        // textContentStorage.delegate) breaks STTextView's layout/selection, which assumes display
        // length == storage length. WYSIWYG hiding is therefore attribute-based (near-zero-width,
        // transparent markers) in LiveWYSIWYGPolicy — storage length stays intact.
        textView.text = text
        coordinator.reparseAndStyle()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.mode = mode
        coordinator.theme = theme
        guard let textView = coordinator.textView else { return }
        textView.backgroundColor = theme.palette.bg
        textView.insertionPointColor = theme.palette.accent
        scrollView.backgroundColor = theme.palette.bg
        if textView.text != text {
            coordinator.isProgrammatic = true
            textView.text = text
            coordinator.isProgrammatic = false
            coordinator.reparseAndStyle()
        } else {
            coordinator.restyle()   // mode/theme may have changed
        }
    }

    final class Coordinator: NSObject, STTextViewDelegate {
        weak var textView: STTextView?
        var mode: RenderMode
        var theme: Theme
        var isProgrammatic = false
        var onChange: ((String) -> Void)?
        let parser = TreeSitterParser()
        private let styler = Styler()
        private var nodes: [SyntaxNode] = []

        init(mode: RenderMode, theme: Theme) {
            self.mode = mode
            self.theme = theme
        }

        private var policy: StylePolicy {
            mode == .liveWYSIWYG ? LiveWYSIWYGPolicy() : SyntaxVisiblePolicy()
        }

        /// Re-parse (text changed) then style with caret awareness.
        func reparseAndStyle() {
            nodes = parser.parse(textView?.text ?? "")
            restyle()
        }

        /// Re-apply styling using the cached parse, revealing markers under the caret.
        func restyle() {
            guard let textView else { return }
            styler.apply(to: textView, nodes: nodes, policy: policy, theme: theme,
                         revealLocation: textView.textSelection.location)
        }

        func textViewDidChangeText(_ notification: Notification) {
            reparseAndStyle()
            if !isProgrammatic, let text = textView?.text { onChange?(text) }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            restyle()   // reveal/collapse markers as the caret moves
        }
    }
}
