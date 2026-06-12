import SwiftUI
import AppKit
import STTextView
import MarkdownCore

/// SwiftUI host for the TextKit 2 editor (STTextView). Phase 2: renders a document in either editing
/// model via the shared Styler. Re-styles on every edit; full incremental/debounced restyle and
/// marker hiding land in the rest of Phase 2.
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

        textView.text = text
        coordinator.restyle()
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
        }
        coordinator.restyle()
    }

    final class Coordinator: NSObject, STTextViewDelegate {
        weak var textView: STTextView?
        var mode: RenderMode
        var theme: Theme
        var isProgrammatic = false
        var onChange: ((String) -> Void)?
        private let styler = Styler()

        init(mode: RenderMode, theme: Theme) {
            self.mode = mode
            self.theme = theme
        }

        private var policy: StylePolicy {
            mode == .liveWYSIWYG ? LiveWYSIWYGPolicy() : SyntaxVisiblePolicy()
        }

        func restyle() {
            guard let textView else { return }
            styler.apply(to: textView, source: textView.text ?? "", policy: policy, theme: theme)
        }

        func textViewDidChangeText(_ notification: Notification) {
            restyle()
            if !isProgrammatic, let text = textView?.text { onChange?(text) }
        }
    }
}
