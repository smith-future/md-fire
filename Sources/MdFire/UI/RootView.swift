import SwiftUI
import MarkdownCore

/// The real app shell (Phase 3): a single editor in a fixed, centered reading column on a full-bleed
/// canvas, with a slim bottom status bar carrying the mode toggle, measure, and word count. Replaces
/// the side-by-side dev harness. Sidebar (file tree + outline) arrives in Phase 5.
struct RootView: View {
    @State private var text = Self.sample
    @State private var mode: RenderMode = .liveWYSIWYG
    @State private var measure = 72
    @State private var isDark = false

    private var theme: Theme { isDark ? .dark : .light }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(theme.palette.bg).ignoresSafeArea()

            // Fixed, centered reading column — the iA "measure".
            TextKitEditor(text: text, mode: mode, theme: theme)
                .frame(maxWidth: theme.columnWidth(chars: measure))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            statusBar
        }
        .preferredColorScheme(isDark ? .dark : .light)
    }

    private var statusBar: some View {
        HStack(spacing: 14) {
            Picker("", selection: $mode) {
                ForEach(RenderMode.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 150)

            Picker("", selection: $measure) {
                ForEach([64, 72, 80], id: \.self) { Text("\($0)").tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 130)

            Button {
                isDark.toggle()
            } label: {
                Image(systemName: isDark ? "sun.max" : "moon")
            }
            .buttonStyle(.borderless)

            Spacer()

            Text("\(wordCount) words")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private var wordCount: Int {
        text.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
    }

    static let sample = """
    # md-fire

    A native macOS editor: **Typora** live preview × _iA Writer_ focus.

    ## Why it exists

    One Markdown source, two modes. Switch with the toggle below — the text never changes,
    only how `markers` are shown. Inline `code`, **strong**, _emphasis_, and ~~strikethrough~~.

    ### Checklist

    - [x] tree-sitter parser
    - [x] native gap-free WYSIWYG
    - [ ] focus & typewriter mode

    > Presentation never touches the file. What you save is plain Markdown.

    ```swift
    let engine = TextKitEditor(text: source, mode: .liveWYSIWYG)
    ```

    See [the design docs](docs/PRODUCT.md) for the full plan.
    """
}
