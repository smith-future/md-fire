import SwiftUI
import MarkdownCore

/// The real app shell (Phase 3): a single editor in a fixed, centered reading column on a full-bleed
/// canvas, with a slim bottom status bar carrying the mode toggle, measure, and word count. Sidebar
/// (file tree + outline) arrives in Phase 5.
struct RootView: View {
    let document: MarkdownDocument

    @State private var mode: RenderMode = .liveWYSIWYG
    @State private var measure = 72
    @State private var isDark = false

    private var theme: Theme { isDark ? .dark : .light }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(theme.palette.bg).ignoresSafeArea()

            // Fixed, centered reading column — the iA "measure".
            TextKitEditor(
                text: document.text,
                mode: mode,
                theme: theme,
                onChange: { document.userEdited($0) }
            )
            .frame(maxWidth: theme.columnWidth(chars: measure))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            statusBar
        }
        .preferredColorScheme(isDark ? .dark : .light)
        .navigationTitle(document.displayName)
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

            Button { isDark.toggle() } label: {
                Image(systemName: isDark ? "sun.max" : "moon")
            }
            .buttonStyle(.borderless)

            Spacer()

            Text(document.displayName + (document.isDirty ? " •" : ""))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            Text("·").foregroundStyle(.tertiary)

            Text("\(wordCount) words")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private var wordCount: Int {
        document.text.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
    }
}
