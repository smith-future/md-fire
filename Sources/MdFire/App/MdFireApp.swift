import SwiftUI
import MarkdownCore

/// md-fire — a native macOS markdown editor fusing Typora's live WYSIWYG with
/// iA Writer's focus + typography. Phase 2: the dual-mode TextKit 2 engine.
///
/// See docs/PRODUCT.md, docs/ARCHITECTURE.md, docs/UI-DESIGN.md, docs/BUILD-PLAN.md.
@main
struct MdFireApp: App {
    var body: some Scene {
        WindowGroup {
            DevHarnessView()
                .frame(minWidth: 640, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)               // UI-DESIGN §4.1: chromeless
        .defaultSize(width: 1000, height: 720)      // UI-DESIGN §4.1: default window
    }
}

/// Phase-2 development harness: the SAME source rendered side by side in both editing models, proving
/// they are one pipeline with two policies. Replaced by RootView (sidebar + status bar, single view
/// with a mode toggle) in Phase 3.
private struct DevHarnessView: View {
    @State private var text = Self.sample

    var body: some View {
        HStack(spacing: 0) {
            pane("Source — iA syntax-visible", mode: .syntaxVisible)
            Divider()
            pane("Live — Typora WYSIWYG", mode: .liveWYSIWYG)
        }
    }

    private func pane(_ title: String, mode: RenderMode) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary)

            TextKitEditor(text: text, mode: mode)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    static let sample = """
    # md-fire

    A native macOS editor: **Typora** live preview × _iA Writer_ focus.

    ## Why it exists

    One Markdown source, two modes. Switch with the toggle below — the text never changes,
    only how `markers` are shown. Inline `code`, **strong**, _emphasis_, and ~~strikethrough~~.

    ### Checklist

    - [x] tree-sitter parser
    - [x] range mapping
    - [ ] live marker hiding

    > Presentation never touches the file. What you save is plain Markdown.

    ```swift
    let engine = TextKitEditor(text: source, mode: .liveWYSIWYG)
    ```

    See [the design docs](docs/PRODUCT.md) for the full plan.
    """
}
