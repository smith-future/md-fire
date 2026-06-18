import AppKit
import STTextView
import MarkdownCore

/// Applies a `StylePolicy`'s attributes over already-parsed nodes. Identical for both editing
/// models — it just asks the policy for content + marker attributes and writes them. The Coordinator
/// parses once and shares the nodes with both the Styler and the MarkupHider.
struct Styler {
    /// `revealLocation` is the caret offset (or nil). In WYSIWYG mode, the element containing the
    /// caret shows its markers (reveal) instead of collapsing them. `focusActive`, when set, is the
    /// bright Focus-Mode range — everything outside it is dimmed.
    func apply(to textView: STTextView, nodes: [SyntaxNode], policy: StylePolicy, theme: Theme,
               revealLocation: Int? = nil, focusActive: NSRange? = nil,
               posTags: [(NSRange, NSColor)] = [], bionicRanges: [NSRange] = []) {
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

        // Bionic reading: bold the leading part of each word, preserving its current size/family.
        if !bionicRanges.isEmpty,
           let storage = (textView.textContentManager as? NSTextContentStorage)?.textStorage {
            for range in bionicRanges where isValid(range, nsLen) && range.length > 0 {
                let base = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont) ?? theme.bodyFont
                let bold = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
                textView.addAttributes([.font: bold], range: range)
            }
        }

        // Parts-of-speech highlight (iA): colour words by lexical class. Editor-only; applied before
        // Focus so dimming still wins outside the active span.
        for (range, color) in posTags where isValid(range, nsLen) {
            textView.addAttributes([.foregroundColor: color], range: range)
        }

        // Focus Mode: a "spotlight" — the active span is full color; text fades to dim with distance,
        // a soft glow falloff rather than a hard bright/dim edge.
        if let active = focusActive {
            applyFocusGlow(textView, active: active, nsLen: nsLen, theme: theme)
        }
    }

    /// Graduated dimming around the active span. Within `falloff` characters of the active edges the
    /// color is interpolated body→dimmed in small bands (the gradient); beyond that it is fully dimmed
    /// in one shot (cheap on long documents).
    private func applyFocusGlow(_ textView: STTextView, active: NSRange, nsLen: Int, theme: Theme) {
        let falloff = 48   // short, crisp glow so the active-scope size (sentence vs paragraph) reads clearly
        let band = 10
        let body = theme.palette.body
        let dimmed = theme.palette.dimmed

        func gradient(from start: Int, to end: Int, distance: (Int) -> Int) {
            var pos = start
            while pos < end {
                let stop = min(pos + band, end)
                let t = min(1, max(0, CGFloat(distance((pos + stop) / 2)) / CGFloat(falloff)))
                let range = NSRange(location: pos, length: stop - pos)
                if isValid(range, nsLen) {
                    textView.addAttributes([.foregroundColor: lerp(body, dimmed, t)], range: range)
                }
                pos = stop
            }
        }

        // Head: uniform dim far from the active edge, then a gradient up to it.
        let headEnd = active.location
        if headEnd > 0 {
            let glowStart = max(0, headEnd - falloff)
            let solid = NSRange(location: 0, length: glowStart)
            if solid.length > 0, isValid(solid, nsLen) {
                textView.addAttributes([.foregroundColor: dimmed], range: solid)
            }
            gradient(from: glowStart, to: headEnd) { headEnd - $0 }
        }

        // Tail: a gradient away from the active edge, then uniform dim.
        let activeEnd = active.location + active.length
        if activeEnd < nsLen {
            let glowEnd = min(nsLen, activeEnd + falloff)
            gradient(from: activeEnd, to: glowEnd) { $0 - activeEnd }
            let solid = NSRange(location: glowEnd, length: nsLen - glowEnd)
            if solid.length > 0, isValid(solid, nsLen) {
                textView.addAttributes([.foregroundColor: dimmed], range: solid)
            }
        }
    }

    /// sRGB linear interpolation between two colors.
    private func lerp(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
        let ca = a.usingColorSpace(.sRGB) ?? a
        let cb = b.usingColorSpace(.sRGB) ?? b
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * t }
        return NSColor(srgbRed: mix(ca.redComponent, cb.redComponent),
                       green: mix(ca.greenComponent, cb.greenComponent),
                       blue: mix(ca.blueComponent, cb.blueComponent),
                       alpha: 1)
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
