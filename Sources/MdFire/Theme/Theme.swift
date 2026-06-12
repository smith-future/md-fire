import AppKit

/// Minimal Phase-2 theme: the colors, fonts, and metrics the Styler needs. Expanded into the full
/// design system (ThemePalette / Typography / ThemeCSS) in Phase 3. Values are the exact hexes from
/// UI-DESIGN.md (the two iA-confirmed ones plus the approximated set).
public struct Theme {
    public struct Palette {
        public let bg: NSColor
        public let body: NSColor
        public let dimmed: NSColor
        public let marker: NSColor
        public let accent: NSColor
        public let codeBg: NSColor
        public let selection: NSColor
    }

    public let palette: Palette
    public let baseSize: CGFloat
    public let lineHeightMultiple: CGFloat

    public func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return baseSize * 1.8
        case 2: return baseSize * 1.5
        case 3: return baseSize * 1.3
        case 4: return baseSize * 1.15
        default: return baseSize
        }
    }

    /// Monospaced writing font (Phase 3 swaps in the bundled iA-style / differentiated face).
    public func font(size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
        let base = NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
        guard italic else { return base }
        return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
    }

    public var bodyFont: NSFont { font(size: baseSize) }

    public func paragraphStyle() -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = lineHeightMultiple
        return p
    }

    public static let light = Theme(
        palette: Palette(
            bg: NSColor(rgb: 0xF5F6F6),
            body: NSColor(rgb: 0x424242),
            dimmed: NSColor(rgb: 0xC6C5C2),
            marker: NSColor(rgb: 0xB0B0AE),
            accent: NSColor(rgb: 0x15BDEC),
            codeBg: NSColor(rgb: 0xEFEFEF),
            selection: NSColor(rgb: 0xCEE7F3)
        ),
        baseSize: 17,
        lineHeightMultiple: 1.5
    )

    public static let dark = Theme(
        palette: Palette(
            bg: NSColor(rgb: 0x1B1B1B),
            body: NSColor(rgb: 0xC5C9C6),
            dimmed: NSColor(rgb: 0x706F70),
            marker: NSColor(rgb: 0x5E5E5E),
            accent: NSColor(rgb: 0x15BDEC),
            codeBg: NSColor(rgb: 0x242424),
            selection: NSColor(rgb: 0x29434E)
        ),
        baseSize: 17,
        lineHeightMultiple: 1.5
    )
}

public extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
