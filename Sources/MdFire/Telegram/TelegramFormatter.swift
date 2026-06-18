import AppKit
import MarkdownCore

/// Converts the document to **Telegram's own message-markdown** and copies it as plain text.
/// Telegram for macOS does not honour rich-text (RTF / attributed string) on paste, but it DOES
/// auto-format its markdown markers (`**bold**`, `__italic__`, `~~strike~~`, `` `code` ``,
/// ```` ```pre``` ````). So we emit those: headings become bold (Telegram has no headings) and
/// single-delimiter emphasis (`_x_` / `*x*`) becomes double-underscore italic (`__x__`). Everything
/// already in Telegram syntax (strong, code, strikethrough, lists, quotes) is left untouched.
enum TelegramFormatter {
    private static let parser = TreeSitterParser()

    static func telegramMarkdown(from markdown: String) -> String {
        let length = (markdown as NSString).length
        var edits: [(range: NSRange, replacement: String)] = []

        func valid(_ r: NSRange) -> Bool { r.location >= 0 && NSMaxRange(r) <= length }

        for node in parser.parse(markdown) {
            switch node.role {
            case .heading:
                // Replace the "## " marker run with "**" and append "**" after the title.
                let prefix = NSRange(location: node.nodeRange.location,
                                     length: node.contentRange.location - node.nodeRange.location)
                let suffix = NSRange(location: NSMaxRange(node.contentRange), length: 0)
                if valid(prefix), prefix.length > 0 { edits.append((prefix, "**")) }
                if valid(suffix) { edits.append((suffix, "**")) }
            case .emphasis:
                // Single-delimiter italic -> Telegram's double-underscore italic.
                for delimiter in node.markerRanges where valid(delimiter) {
                    edits.append((delimiter, "__"))
                }
            default:
                break   // strong (**), code (`), strikethrough (~~), lists, quotes already TG-valid
            }
        }

        let result = NSMutableString(string: markdown)
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            guard NSMaxRange(edit.range) <= result.length else { continue }
            result.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        return result as String
    }

    /// Copy the Telegram-markdown version to the pasteboard as plain text.
    static func copyToPasteboard(from markdown: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(telegramMarkdown(from: markdown), forType: .string)
    }
}
