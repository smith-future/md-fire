import SwiftUI

/// The floating formatting bar shown above a text selection. The marker buttons wrap the selection
/// in Markdown; the trailing button copies the selected text in Telegram-markdown for pasting.
struct FormatBar: View {
    let apply: (InlineFormat) -> Void
    let copyTelegram: () -> Void

    @State private var copied = false

    var body: some View {
        HStack(spacing: 1) {
            headingButton(1)
            headingButton(2)
            headingButton(3)

            Divider().frame(height: 18)

            button("bold", .bold, help: "Bold")
            button("italic", .italic, help: "Italic")
            button("curlybraces", .code, help: "Code")
            button("strikethrough", .strikethrough, help: "Strikethrough")

            Divider().frame(height: 18)

            Button {
                copyTelegram()
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "paperplane.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(copied ? Color.green : Color.accentColor)
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(copied ? "Copied!" : "Copy selection for Telegram")
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

    private func headingButton(_ level: Int) -> some View {
        Button { apply(.heading(level)) } label: {
            Text("H\(level)")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Heading \(level) (toggle)")
    }
}
