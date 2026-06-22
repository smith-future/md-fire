import SwiftUI
import AppKit
import NaturalLanguage
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
    var posHighlight: Bool = false
    var bionic: Bool = false
    var reduceMotion: Bool = false
    var controller: EditorController? = nil
    var onChange: ((String) -> Void)? = nil
    var onCheckboxToggle: (() -> Void)? = nil
    var onFollowLink: ((String) -> Void)? = nil
    var onActivated: (() -> Void)? = nil
    /// F1: line ranges the last external reload changed (already gated by Show-changes upstream).
    var changedRanges: [NSRange] = []
    /// F1: bumped by the document on each external reload, so we reload in place vs hard-reset.
    var reloadGeneration: Int = 0

    func makeCoordinator() -> Coordinator { Coordinator(mode: mode, theme: theme) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = FillingTextView.scrollableTextView()
        // swiftlint:disable:next force_cast
        let textView = scrollView.documentView as! STTextView
        let coordinator = context.coordinator
        coordinator.textView = textView
        coordinator.onChange = onChange
        coordinator.onCheckboxToggle = onCheckboxToggle
        coordinator.onFollowLink = onFollowLink
        coordinator.onActivated = onActivated
        coordinator.focusScope = focusScope
        coordinator.typewriter = typewriter
        coordinator.posHighlight = posHighlight
        coordinator.bionic = bionic
        coordinator.reduceMotion = reduceMotion

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
        coordinator.onCheckboxToggle = onCheckboxToggle
        coordinator.onFollowLink = onFollowLink
        coordinator.onActivated = onActivated
        let appearanceChanged = coordinator.mode != mode
            || coordinator.theme.palette.bg != theme.palette.bg
            || coordinator.focusScope != focusScope
            || coordinator.posHighlight != posHighlight
            || coordinator.bionic != bionic
        let typewriterChanged = coordinator.typewriter != typewriter
        coordinator.mode = mode
        coordinator.theme = theme
        coordinator.focusScope = focusScope
        coordinator.typewriter = typewriter
        coordinator.posHighlight = posHighlight
        coordinator.bionic = bionic
        coordinator.reduceMotion = reduceMotion   // read live in didScroll; no restyle needed
        guard let textView = coordinator.textView else { return }
        textView.backgroundColor = theme.palette.bg
        textView.insertionPointColor = theme.palette.accent
        scrollView.backgroundColor = theme.palette.bg

        if typewriterChanged { coordinator.configureTypewriter(typewriter) }

        if textView.text != text {
            if reloadGeneration != coordinator.lastReloadGeneration {
                // F1: an agent rewrote the file on disk — reload in place (keep the viewport) and
                // tint the changed lines.
                coordinator.lastReloadGeneration = reloadGeneration
                coordinator.reloadPreservingViewport(newText: text, changedRanges: changedRanges)
            } else {
                // A different document was opened (sidebar / ⌘O / New) — hard reset to the top.
                coordinator.isProgrammatic = true
                textView.text = text
                coordinator.isProgrammatic = false
                coordinator.reparseAndStyle()
            }
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
        var onCheckboxToggle: (() -> Void)?        // F2: persist a checkbox tick to disk
        var onFollowLink: ((String) -> Void)?      // F4: resolve + open an internal link destination
        var onActivated: (() -> Void)?             // F5: mark this pane active (focused) for menu routing
        var focusScope: FocusScope = .off
        var typewriter = false
        var posHighlight = false
        var bionic = false
        var reduceMotion = false
        let parser = TreeSitterParser()
        private let styler = Styler()
        private var nodes: [SyntaxNode] = []
        private var posTags: [(NSRange, NSColor)] = []
        private var bionicRanges: [NSRange] = []

        // F1: transient change-highlight state.
        var lastReloadGeneration = 0
        private var changedRanges: [NSRange] = []
        private var changeAlpha: CGFloat = 0
        private var changeDecayWork: DispatchWorkItem?

        private var lastFocusActive: NSRange?
        private var isRestyling = false
        private var formatBarWork: DispatchWorkItem?
        private lazy var formatPopover: NSPopover = {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = false
            popover.contentViewController = NSHostingController(
                rootView: FormatBar(
                    apply: { [weak self] format in self?.applyFormat(format) },
                    copyTelegram: { [weak self] in self?.copySelectionToTelegram() }
                )
            )
            popover.contentSize = NSSize(width: 170, height: 30)
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
            // Reduce Motion: don't let the Focus spotlight chase the scroll — it re-lights only on
            // caret moves (textViewDidChangeSelection), so reading no longer animates a moving band.
            guard !reduceMotion else { return }
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
            let text = textView?.text ?? ""
            nodes = parser.parse(text)
            posTags = posHighlight ? Self.partsOfSpeech(in: text) : []
            bionicRanges = bionic ? Self.bionicBoldRanges(in: text) : []
            restyle()
        }

        /// Leading ~45% of each word — the Bionic-reading bold span.
        static func bionicBoldRanges(in text: String) -> [NSRange] {
            guard !text.isEmpty else { return [] }
            var out: [NSRange] = []
            text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords]) { sub, range, _, _ in
                guard let sub, !sub.isEmpty else { return }
                let nsRange = NSRange(range, in: text)
                let bold = max(1, Int((Double(sub.count) * 0.45).rounded()))
                out.append(NSRange(location: nsRange.location, length: min(bold, nsRange.length)))
            }
            return out
        }

        /// Words coloured by lexical class (NaturalLanguage). Computed on text/toggle change, cached.
        static func partsOfSpeech(in text: String) -> [(NSRange, NSColor)] {
            guard !text.isEmpty else { return [] }
            let tagger = NLTagger(tagSchemes: [.lexicalClass])
            tagger.string = text
            var out: [(NSRange, NSColor)] = []
            tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word,
                                 scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, range in
                if let tag, let color = posColor(tag) {
                    out.append((NSRange(range, in: text), color))
                }
                return true
            }
            return out
        }

        private static func posColor(_ tag: NLTag) -> NSColor? {
            switch tag {
            case .noun: return NSColor(rgb: 0xC8402F)        // red
            case .verb: return NSColor(rgb: 0x2E7DD1)        // blue
            case .adjective: return NSColor(rgb: 0x9A6A3A)   // brown
            case .adverb: return NSColor(rgb: 0x8E5BA6)      // purple
            case .conjunction: return NSColor(rgb: 0x4F9A4F) // green
            default: return nil
            }
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
                         revealLocation: caret, focusActive: focusActive, posTags: posTags,
                         bionicRanges: bionicRanges, changedRanges: changedRanges, changeAlpha: changeAlpha)
            if typewriter { centerCaretLine() }
        }

        // MARK: - F1 live reload (preserve viewport) + change-tint decay

        /// Swap in externally-changed text WITHOUT the hard reset that jumps the scroll to the top:
        /// capture scroll origin + selection, set the text, reparse/restyle, then restore them. Starts
        /// the change-tint decay over `changedRanges`.
        func reloadPreservingViewport(newText: String, changedRanges: [NSRange]) {
            guard let textView else { return }
            let scroll = textView.enclosingScrollView
            let savedOrigin = scroll?.contentView.bounds.origin
            let savedSelection = textView.textSelection
            // Set the highlight state BEFORE the text swap so the single (explicit) reparseAndStyle
            // already tints; textViewDidChangeText skips its own reparse while isProgrammatic.
            self.changedRanges = changedRanges
            self.changeAlpha = changedRanges.isEmpty ? 0 : 1
            isProgrammatic = true
            textView.text = newText
            isProgrammatic = false
            reparseAndStyle()
            if let scroll, let origin = savedOrigin {
                scroll.contentView.scroll(to: origin)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            let len = (newText as NSString).length
            if NSMaxRange(savedSelection) <= len { textView.textSelection = savedSelection }
            startChangeDecay()
        }

        /// Hold the tint at full strength briefly, then fade it out in small steps (snapping under
        /// Reduce Motion). Mirrors the status-bar fade-on-idle pattern.
        private func startChangeDecay() {
            changeDecayWork?.cancel()
            guard !changedRanges.isEmpty else { changeAlpha = 0; return }
            changeAlpha = 1
            restyle()
            if reduceMotion {
                let work = DispatchWorkItem { [weak self] in self?.clearChangeHighlight() }
                changeDecayWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
                return
            }
            let steps = 10
            func fade(_ i: Int) {
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    if i > steps { self.clearChangeHighlight(); return }
                    self.changeAlpha = 1 - CGFloat(i) / CGFloat(steps)
                    self.restyle()
                    fade(i + 1)
                }
                changeDecayWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + (i == 0 ? 0.8 : 0.13), execute: work)
            }
            fade(0)
        }

        private func clearChangeHighlight() {
            changedRanges = []
            changeAlpha = 0
            restyle()
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
        /// Clamps to the current text length, so a stale search range (the file was rewritten between
        /// indexing and the jump) lands at the end instead of being silently dropped.
        func reveal(_ range: NSRange) {
            guard let textView else { return }
            let length = (textView.text as NSString?)?.length ?? 0
            let location = min(max(0, range.location), length)
            textView.textSelection = NSRange(location: location, length: 0)
            guard let scroll = textView.enclosingScrollView else { return }
            let layout = textView.textLayoutManager
            let content = textView.textContentManager
            guard let loc = content.location(layout.documentRange.location, offsetBy: location),
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

        /// Copy the current selection, converted to Telegram-markdown, to the pasteboard.
        func copySelectionToTelegram() {
            guard let textView else { return }
            let selection = textView.textSelection
            guard selection.length > 0 else { return }
            let ns = (textView.text ?? "") as NSString
            guard NSMaxRange(selection) <= ns.length else { return }
            TelegramFormatter.copyToPasteboard(from: ns.substring(with: selection))
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

        // MARK: - Link & checkbox clicks (F2 / F4)

        /// STTextView calls this on a click within a `.link` range. Returning `true` means we handled
        /// it (suppresses the default NSWorkspace.open). We dispatch by scheme: `mdfire://toggle`
        /// flips a checkbox, `mdfire://open?path=` follows an internal link, anything else (http…)
        /// returns false so STTextView opens it in the browser.
        func textView(_ textView: STTextView, clickedOnLink link: Any, at location: any NSTextLocation) -> Bool {
            guard let url = (link as? URL) ?? (link as? String).flatMap({ URL(string: $0) }) else { return false }
            guard url.scheme == "mdfire" else { return false }
            switch url.host {
            case "toggle":
                return toggleCheckbox(at: location)
            case "open":
                let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "path" }?.value
                if let path, let onFollowLink { onFollowLink(path); return true }
                return false
            default:
                return false
            }
        }

        /// Flip the `[ ]`/`[x]` at the clicked location and write it back into the buffer (which the
        /// onCheckboxToggle hook then persists to disk). Re-parses current text so the range is fresh.
        private func toggleCheckbox(at location: any NSTextLocation) -> Bool {
            guard let textView else { return false }
            let layout = textView.textLayoutManager
            let content = textView.textContentManager
            let offset = content.offset(from: layout.documentRange.location, to: location)
            let text = textView.text ?? ""
            let ns = text as NSString
            guard offset >= 0, offset <= ns.length else { return false }
            // Match the checkbox on the CLICKED LINE — robust to caret-location imprecision at edges.
            let probe = NSRange(location: min(offset, max(0, ns.length - 1)), length: 0)
            let line = ns.lineRange(for: probe)
            let hit = parser.parse(text).first { node in
                if case .taskItem = node.role, let cb = node.checkboxRange {
                    return NSLocationInRange(cb.location, line)
                }
                return false
            }
            guard let cb = hit?.checkboxRange, NSMaxRange(cb) <= ns.length else { return false }
            let toggled = ns.substring(with: cb).lowercased().contains("x") ? "[ ]" : "[x]"
            textView.insertText(toggled, replacementRange: cb)
            onCheckboxToggle?()
            return true
        }

        func textViewDidChangeText(_ notification: Notification) {
            // Programmatic text swaps (open / external reload) restyle explicitly via reparseAndStyle;
            // skip here so we don't reparse twice.
            guard !isProgrammatic else { return }
            reparseAndStyle()
            if let text = textView?.text { onChange?(text) }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            onActivated?()        // this pane is the one the user is interacting with (split routing)
            restyle()             // reveal/collapse markers + Focus + typewriter follow the caret
            scheduleFormatBar()   // show the formatting bar over a non-empty selection
        }
    }
}
