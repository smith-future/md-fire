import Foundation
import Markdown

/// Renders the document to a self-contained, themed HTML string (CSS inlined, no external deps).
/// Used by both HTML export and (loaded in a WKWebView) PDF export. Walks swift-markdown's AST so
/// the output is conformant GFM.
enum HTMLRenderer {
    static func standaloneHTML(from markdown: String, title: String, dark: Bool) -> String {
        let body = html(for: Document(parsing: markdown))
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(title))</title>
        <style>\(css(dark: dark))</style>
        </head>
        <body>
        <article>
        \(body)
        </article>
        </body>
        </html>
        """
    }

    // MARK: - AST -> HTML

    private static func html(for markup: Markup) -> String {
        switch markup {
        case let node as Document:
            return children(node)
        case let node as Heading:
            return "<h\(node.level)>\(children(node))</h\(node.level)>\n"
        case let node as Paragraph:
            return "<p>\(children(node))</p>\n"
        case let node as Text:
            return escape(node.string)
        case let node as Strong:
            return "<strong>\(children(node))</strong>"
        case let node as Emphasis:
            return "<em>\(children(node))</em>"
        case let node as Strikethrough:
            return "<del>\(children(node))</del>"
        case let node as InlineCode:
            return "<code>\(escape(node.code))</code>"
        case let node as CodeBlock:
            let lang = node.language.map { " class=\"language-\(escape($0))\"" } ?? ""
            return "<pre><code\(lang)>\(escape(node.code))</code></pre>\n"
        case let node as Link:
            return "<a href=\"\(escape(node.destination ?? ""))\">\(children(node))</a>"
        case let node as Image:
            return "<img src=\"\(escape(node.source ?? ""))\" alt=\"\(escape(node.plainText))\">"
        case let node as UnorderedList:
            return "<ul>\n\(children(node))</ul>\n"
        case let node as OrderedList:
            return "<ol>\n\(children(node))</ol>\n"
        case let node as ListItem:
            let box: String
            switch node.checkbox {
            case .checked: box = "<input type=\"checkbox\" checked disabled> "
            case .unchecked: box = "<input type=\"checkbox\" disabled> "
            case nil: box = ""
            }
            return "<li>\(box)\(children(node))</li>\n"
        case let node as BlockQuote:
            return "<blockquote>\n\(children(node))</blockquote>\n"
        case is ThematicBreak:
            return "<hr>\n"
        case is SoftBreak:
            return " "
        case is LineBreak:
            return "<br>\n"
        case let node as InlineHTML:
            return node.rawHTML
        case let node as HTMLBlock:
            return node.rawHTML
        default:
            return children(markup)
        }
    }

    private static func children(_ markup: Markup) -> String {
        markup.children.map { html(for: $0) }.joined()
    }

    private static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(ch)
            }
        }
        return out
    }

    // MARK: - Theme CSS (matches the editor's iA aesthetic)

    private static func css(dark: Bool) -> String {
        let bg = dark ? "#1B1B1B" : "#F5F6F6"
        let text = dark ? "#C5C9C6" : "#424242"
        let dim = dark ? "#706F70" : "#9A9A98"
        let accent = "#15BDEC"
        let codeBg = dark ? "#242424" : "#EFEFEF"
        let border = dark ? "#2A2A2A" : "#E0E0E0"
        return """
        :root { color-scheme: \(dark ? "dark" : "light"); }
        * { box-sizing: border-box; }
        body {
          margin: 0; background: \(bg); color: \(text);
          font: 17px/1.6 -apple-system, "SF Pro Text", system-ui, sans-serif;
          -webkit-font-smoothing: antialiased;
        }
        article { max-width: 42rem; margin: 0 auto; padding: 64px 24px 96px; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.6em 0 0.6em; font-weight: 700; }
        h1 { font-size: 1.9em; } h2 { font-size: 1.5em; } h3 { font-size: 1.3em; }
        h4 { font-size: 1.15em; } h5 { font-size: 1em; } h6 { font-size: 1em; color: \(dim); }
        p { margin: 0 0 1em; }
        a { color: \(accent); text-decoration: none; } a:hover { text-decoration: underline; }
        strong { font-weight: 700; } em { font-style: italic; } del { color: \(dim); }
        code { font: 0.92em ui-monospace, "SF Mono", Menlo, monospace; background: \(codeBg);
               padding: 0.15em 0.35em; border-radius: 4px; }
        pre { background: \(codeBg); padding: 14px 16px; border-radius: 8px; overflow: auto; }
        pre code { background: none; padding: 0; }
        blockquote { margin: 1em 0; padding: 0.2em 0 0.2em 1em; border-left: 3px solid \(accent);
                     color: \(dim); font-style: italic; }
        ul, ol { padding-left: 1.4em; margin: 0 0 1em; }
        li { margin: 0.25em 0; }
        li input[type=checkbox] { margin-right: 0.4em; }
        hr { border: none; border-top: 1px solid \(border); margin: 2em 0; }
        img { max-width: 100%; }
        table { border-collapse: collapse; margin: 1em 0; }
        th, td { border: 1px solid \(border); padding: 6px 10px; }
        @media print { body { background: #fff; } article { padding: 0; max-width: none; } }
        """
    }
}
