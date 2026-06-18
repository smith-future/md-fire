import SwiftUI

/// The floating formatting bar shown above a text selection. Buttons wrap the selection in Markdown.
struct FormatBar: View {
    let apply: (InlineFormat) -> Void

    var body: some View {
        HStack(spacing: 1) {
            button("bold", .bold, help: "Bold")
            button("italic", .italic, help: "Italic")
            button("curlybraces", .code, help: "Code")
            button("strikethrough", .strikethrough, help: "Strikethrough")
        }
        .padding(3)
    }

    private func button(_ icon: String, _ format: InlineFormat, help: String) -> some View {
        Button { apply(format) } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
