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
    var focusScope: FocusScope = .off
    var typewriter: Bool = false
    var controller: EditorController? = nil
    var onChange: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(mode: mode, theme: theme) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = FillingTextView.scrollableTextView()
        // swiftlint:disable:next force_cast
        let textView = scrollView.documentView as! STTextView
        let coordinator = context.coordinator
        coordinator.textView = textView
        coordinator.onChange = onChange
        coordinator.focusScope = focusScope
        coordinator.typewriter = typewriter

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
        coordinator.observeScroll(scrollView)
        controller?.revealHandler = { [weak coordinator] range in coordinator?.reveal(range) }
        controller?.formatHandler = { [weak coordinator] format in coordinator?.applyFormat(format) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        let appearanceChanged = coordinator.mode != mode
            || coordinator.theme.palette.bg != theme.palette.bg
            || coordinator.focusScope != focusScope
        let typewriterChanged = coordinator.typewriter != typewriter
        coordinator.mode = mode
        coordinator.theme = theme
        coordinator.focusScope = focusScope
        coordinator.typewriter = typewriter
        guard let textView = coordinator.textView else { return }
        textView.backgroundColor = theme.palette.bg
        textView.insertionPointColor = theme.palette.accent
        scrollView.backgroundColor = theme.palette.bg

        if typewriterChanged { coordinator.configureTypewriter(typewriter) }

        if textView.text != text {
            // External change (file opened / new doc) — sync the view and re-parse.
            coordinator.isProgrammatic = true
            textView.text = text
            coordinator.isProgrammatic = false
            coordinator.reparseAndStyle()
        } else if appearanceChanged || typewriterChanged {
            coordinator.reparseAndStyle()   // mode / theme / focus / typewriter toggled
        }
    }

    final class Coordinator: NSObject, STTextViewDelegate {
        weak var textView: STTextView?
        var mode: RenderMode
        var theme: Theme
        var isProgrammatic = false
        var onChange: ((String) -> Void)?
        var focusScope: FocusScope = .off
        var typewriter = false
        let parser = TreeSitterParser()
        private let styler = Styler()
        private var nodes: [SyntaxNode] = []

        private var lastFocusActive: NSRange?
        private var isRestyling = false
        private var formatBarWork: DispatchWorkItem?
        private lazy var formatPopover: NSPopover = {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = false
            popover.contentViewController = NSHostingController(
                rootView: FormatBar(apply: { [weak self] format in self?.applyFormat(format) })
            )
            popover.contentSize = NSSize(width: 130, height: 30)
            return popover
        }()

        init(mode: RenderMode, theme: Theme) {
            self.mode = mode
            self.theme = theme
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        /// Watch the scroll position so Focus can follow it (reading spotlight) when not editing.
        func observeScroll(_ scrollView: NSScrollView) {
            let clip = scrollView.contentView
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(didScroll),
                                                   name: NSView.boundsDidChangeNotification, object: clip)
        }

        @objc private func didScroll() {
            guard focusScope.dims, !isRestyling else { return }
            let candidate = focusActiveRange(caret: focusAnchor())
            guard candidate != lastFocusActive else { return }   // throttle: nothing new to light
            restyle()
        }

        /// Focus anchors at the caret while it's on screen (editing); otherwise at the viewport
        /// centre (reading/scrolling). This makes Focus follow the scroll without ever fighting the
        /// caret during typing.
        private func focusAnchor() -> Int {
            let caret = textView?.textSelection.location ?? 0
            return caretIsVisible() ? caret : (viewportCenterLocation() ?? caret)
        }

        /// True when the caret's line is within the visible area.
        private func caretIsVisible() -> Bool {
            guard let textView, let scroll = textView.enclosingScrollView else { return true }
            let layout = textView.textLayoutManager
            let content = textView.textContentManager
            guard let caretLoc = content.location(layout.documentRange.location,
                                                  offsetBy: textView.textSelection.location),
                  let fragment = layout.textLayoutFragment(for: caretLoc) else { return true }
            return scroll.documentVisibleRect.intersects(fragment.layoutFragmentFrame)
        }

        /// Document offset at the vertical centre of the visible area (via TextKit 2 hit-testing).
        private func viewportCenterLocation() -> Int? {
            guard let textView, let scroll = textView.enclosingScrollView else { return nil }
            let visible = scroll.documentVisibleRect
            guard visible.height > 0 else { return nil }
            let point = CGPoint(x: visible.minX + 24, y: visible.midY)
            let layout = textView.textLayoutManager
            let content = textView.textContentManager
            guard let fragment = layout.textLayoutFragment(for: point) else { return nil }
            let elementStart = content.offset(from: layout.documentRange.location,
                                              to: fragment.rangeInElement.location)
            let localY = point.y - fragment.layoutFragmentFrame.minY
            for line in fragment.textLineFragments {
                let bounds = line.typographicBounds
                if localY >= bounds.minY && localY <= bounds.maxY {
                    return elementStart + line.characterRange.location
                }
            }
            return elementStart
        }

        private var policy: StylePolicy {
            mode == .liveWYSIWYG ? LiveWYSIWYGPolicy() : SyntaxVisiblePolicy()
        }

        /// Re-parse (text changed) then style with caret awareness.
        func reparseAndStyle() {
            nodes = parser.parse(textView?.text ?? "")
            restyle()
        }

        /// Re-apply styling using the cached parse: reveal markers under the caret and dim for Focus.
        /// Focus anchors at the scroll-driven `focusAnchorOverride` when set, else at the caret.
        func restyle() {
            guard let textView else { return }
            isRestyling = true                  // suppress the scroll observer during our own scrolls
            defer { isRestyling = false }
            let caret = textView.textSelection.location
            let anchor = focusAnchor()
            let focusActive = focusActiveRange(caret: anchor)
            lastFocusActive = focusActive
            styler.apply(to: textView, nodes: nodes, policy: policy, theme: theme,
                         revealLocation: caret, focusActive: focusActive)
            if typewriter { centerCaretLine() }
        }

        /// Focus range for the caret. `.line` uses the actual TextKit 2 visual line; the rest comes
        /// from the pure FocusRange (sentence/paragraph).
        private func focusActiveRange(caret: Int) -> NSRange? {
            guard focusScope.dims else { return nil }
            if focusScope == .line, let line = visualLineRange(caret: caret) { return line }
            return FocusRange.active(in: textView?.text ?? "", caret: caret, scope: focusScope)
        }

        /// The document range of the visual (wrapped) line containing the caret, via TextKit 2.
        private func visualLineRange(caret: Int) -> NSRange? {
            guard let textView else { return nil }
            let layout = textView.textLayoutManager
            let content = textView.textContentManager
            guard let caretLoc = content.location(layout.documentRange.location, offsetBy: caret),
                  let fragment = layout.textLayoutFragment(for: caretLoc) else { return nil }
            let elementStart = content.offset(from: layout.documentRange.location,
                                              to: fragment.rangeInElement.location)
            for line in fragment.textLineFragments {
                let docRange = NSRange(location: elementStart + line.characterRange.location,
                                       length: line.characterRange.length)
                if caret >= docRange.location && caret <= docRange.location + docRange.length {
                    return docRange
                }
            }
            return nil
        }

        /// Typewriter scrolling: keep the caret's line vertically centered in the viewport.
        /// Suppressed during drag-selection (a non-empty selection) to avoid the documented
        /// "screen jumping". Layout is settled around the caret before reading the line frame.
        func centerCaretLine() {
            guard let textView, let scroll = textView.enclosingScrollView else { return }
            let selection = textView.textSelection
            guard selection.length == 0 else { return }   // caret only, never mid-drag

            let layout = textView.textLayoutManager
            let content = textView.textContentManager
            guard let caretLoc = content.location(layout.documentRange.location,
                                                  offsetBy: selection.location) else { return }
            layout.ensureLayout(for: NSTextRange(location: caretLoc))
            guard let fragment = layout.textLayoutFragment(for: caretLoc) else { return }

            let visibleHeight = scroll.documentVisibleRect.height
            guard visibleHeight > 0 else { return }
            let targetY = fragment.layoutFragmentFrame.midY - visibleHeight / 2

            let clip = scroll.contentView
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0            // no implicit scroll animation
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: targetY))
            scroll.reflectScrolledClipView(clip)
            NSAnimationContext.endGrouping()
        }

        func configureTypewriter(_ on: Bool) {
            if on { centerCaretLine() }
        }

        /// Outline jump: place the caret at `range.location` and scroll it near the top of the view.
        func reveal(_ range: NSRange) {
            guard let textView else { return }
            textView.textSelection = NSRange(location: range.location, length: 0)
            guard let scroll = textView.enclosingScrollView else { return }
            let layout = textView.textLayoutManager
            let content = textView.textContentManager
            guard let loc = content.location(layout.documentRange.location, offsetBy: range.location),
                  let fragment = layout.textLayoutFragment(for: loc) else { return }
            let clip = scroll.contentView
            let targetY = fragment.layoutFragmentFrame.minY - clip.bounds.height * 0.25
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: max(0, targetY)))
            scroll.reflectScrolledClipView(clip)
        }

        /// Wrap the selection (or insert an empty pair at the caret) in a Markdown marker.
        func applyFormat(_ format: InlineFormat) {
            guard let textView else { return }
            let selection = textView.textSelection
            let marker = format.marker
            let ns = (textView.text ?? "") as NSString
            guard NSMaxRange(selection) <= ns.length else { return }

            if selection.length > 0 {
                let selected = ns.substring(with: selection)
                textView.insertText(marker + selected + marker, replacementRange: selection)
                textView.textSelection = NSRange(location: selection.location + marker.count, length: selection.length)
            } else {
                textView.insertText(marker + marker, replacementRange: selection)
                textView.textSelection = NSRange(location: selection.location + marker.count, length: 0)
            }
        }

        // MARK: - Floating format bar

        /// Bounding rect of the selection in the text view's coordinates.
        private func selectionRect() -> CGRect? {
            guard let textView else { return nil }
            let selection = textView.textSelection
            guard selection.length > 0 else { return nil }
            let layout = textView.textLayoutManager
            let content = textView.textContentManager
            guard let start = content.location(layout.documentRange.location, offsetBy: selection.location),
                  let end = content.location(start, offsetBy: selection.length),
                  let range = NSTextRange(location: start, end: end) else { return nil }
            var rect = CGRect.null
            layout.enumerateTextSegments(in: range, type: .selection, options: []) { _, frame, _, _ in
                rect = rect.isNull ? frame : rect.union(frame)
                return true
            }
            return rect.isNull ? nil : rect
        }

        /// Show the format bar once the selection settles (debounced so it doesn't flicker mid-drag).
        func scheduleFormatBar() {
            formatBarWork?.cancel()
            guard let textView, textView.textSelection.length > 0 else {
                if formatPopover.isShown { formatPopover.performClose(nil) }
                return
            }
            let work = DispatchWorkItem { [weak self] in self?.showFormatBar() }
            formatBarWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }

        private func showFormatBar() {
            guard let textView, textView.textSelection.length > 0, let rect = selectionRect() else { return }
            if formatPopover.isShown { formatPopover.performClose(nil) }
            formatPopover.show(relativeTo: rect, of: textView, preferredEdge: .minY)
        }

        // MARK: - Context menu (add Format, drop the iPhone-continuity clutter)

        func textView(_ textView: STTextView, menu: NSMenu, for event: NSEvent, at location: any NSTextLocation) -> NSMenu? {
            for title in ["Take Photo", "Scan Documents", "Add Sketch", "Insert from iPhone or iPad", "AutoFill"] {
                if let item = menu.items.first(where: { $0.title == title }) { menu.removeItem(item) }
            }
            if textView.textSelection.length > 0 {
                let submenu = NSMenu()
                submenu.addItem(formatItem("Bold", .bold))
                submenu.addItem(formatItem("Italic", .italic))
                submenu.addItem(formatItem("Code", .code))
                submenu.addItem(formatItem("Strikethrough", .strikethrough))
                let root = NSMenuItem(title: "Format", action: nil, keyEquivalent: "")
                root.submenu = submenu
                menu.insertItem(root, at: 0)
                menu.insertItem(.separator(), at: 1)
            }
            return menu
        }

        private func formatItem(_ title: String, _ format: InlineFormat) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(formatMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = format
            return item
        }

        @objc private func formatMenuAction(_ sender: NSMenuItem) {
            if let format = sender.representedObject as? InlineFormat { applyFormat(format) }
        }

        func textViewDidChangeText(_ notification: Notification) {
            reparseAndStyle()
            if !isProgrammatic, let text = textView?.text { onChange?(text) }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            restyle()             // reveal/collapse markers + Focus + typewriter follow the caret
            scheduleFormatBar()   // show the formatting bar over a non-empty selection
        }
    }
}
