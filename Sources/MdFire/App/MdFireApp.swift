import SwiftUI
import MarkdownCore

/// md-fire — a native macOS markdown editor fusing Typora's live WYSIWYG with
/// iA Writer's focus + typography. Phase 0: a runnable empty shell.
///
/// See docs/PRODUCT.md, docs/ARCHITECTURE.md, docs/UI-DESIGN.md, docs/BUILD-PLAN.md.
@main
struct MdFireApp: App {
    var body: some Scene {
        WindowGroup {
            ScaffoldView()
                .frame(minWidth: 640, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)               // UI-DESIGN §4.1: chromeless
        .defaultSize(width: 1000, height: 720)      // UI-DESIGN §4.1: default window
    }
}

/// Temporary Phase-1 placeholder. Replaced by RootView (NavigationSplitView) in Phase 3.
/// Parses a sample through MarkdownCore to prove the engine is wired into the app.
private struct ScaffoldView: View {
    private static let sample = "# md-fire\n\n**Typora** × _iA Writer_. Live `markdown`.\n"
    private let nodeCount = TreeSitterParser().parse(sample).count

    var body: some View {
        ZStack {
            BrandColor.lightCanvas.ignoresSafeArea() // iA confirmed #F5F6F6, never pure white
            VStack(spacing: 6) {
                Text("md-fire")
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .foregroundStyle(BrandColor.lightBody)   // iA confirmed #424242
                Text("Phase 1 — MarkdownCore parsed \(nodeCount) nodes")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(BrandColor.marker)      // ~#B0B0AE
            }
        }
    }
}

/// Minimal color helper for Phase 0. Superseded by Theme/ThemePalette.swift in Phase 3.
private enum BrandColor {
    static let lightCanvas = Color(hex: 0xF5F6F6)
    static let lightBody   = Color(hex: 0x424242)
    static let marker      = Color(hex: 0xB0B0AE)
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
