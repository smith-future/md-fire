import Foundation
import Markdown

/// Renders the document to a self-contained, themed HTML string (CSS inlined, no external deps).
/// Used by both HTML export and (loaded in a WKWebView) PDF export. Walks swift-markdown's AST so
/// the output is conformant GFM.
enum HTMLRenderer {
    /// Static, self-contained themed HTML — used for HTML/PDF export (no JavaScript).
    static func standaloneHTML(from markdown: String, title: String, dark: Bool) -> String {
        """
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
        \(articleBody(from: markdown))
        </article>
        </body>
        </html>
        """
    }

    /// Frontmatter block (if present) + rendered body — shared by export and the live preview.
    static func articleBody(from markdown: String) -> String {
        let (frontmatter, body) = splitFrontmatter(markdown)
        let fmHTML = frontmatter.map { "<div class=\"frontmatter\"><pre>\(escape($0))</pre></div>\n" } ?? ""
        return fmHTML + html(for: Document(parsing: body))
    }

    /// Live preview page (F3): the same body plus highlight.js / Mermaid / KaTeX from CDN and a
    /// `__setBody` hook for flicker-free incremental updates. Renders beautifully online; degrades
    /// gracefully offline (code shows unhighlighted, diagrams as source, math as raw `$…$`). Updates
    /// parse into a detached document and move nodes in (no innerHTML, scripts never execute).
    static func richHTML(from markdown: String, title: String, dark: Bool, columnChars: Int = 72) -> String {
        let hlTheme = dark ? "github-dark" : "github"
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(title))</title>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/styles/\(hlTheme).min.css">
        <style>\(css(dark: dark))</style>
        <style>
          /* On-screen reader: start near the top like the editor (export keeps the big page margins). */
          article { max-width: calc(\(columnChars)ch + 48px); padding-top: 20px; }
          article > :first-child { margin-top: 0; }
        </style>
        <script src="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/highlight.min.js"></script>
        <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/contrib/auto-render.min.js"></script>
        <script>
          function __render() {
            try { if (window.hljs) document.querySelectorAll('pre code').forEach(function(e){ hljs.highlightElement(e); }); } catch (e) {}
            try { if (window.mermaid) { mermaid.initialize({ startOnLoad: false, theme: '\(dark ? "dark" : "default")' }); mermaid.run({ querySelector: '.mermaid' }); } } catch (e) {}
            try { if (window.renderMathInElement) renderMathInElement(document.body, { delimiters: [{left:'$$',right:'$$',display:true},{left:'$',right:'$',display:false}], throwOnError: false }); } catch (e) {}
          }
          // Parse into a detached document (scripts never run) and move the nodes in — no innerHTML.
          window.__setBody = function(html, resetScroll) {
            var article = document.getElementById('article');
            if (!article) return;
            var parsed = new DOMParser().parseFromString(html, 'text/html');
            article.replaceChildren.apply(article, Array.prototype.slice.call(parsed.body.childNodes));
            if (resetScroll) window.scrollTo(0, 0);
            __render();
          };
          // Interactive task checkboxes: a change posts the checkbox's index (DOM order == file order)
          // to the app, which toggles the matching `[ ]`/`[x]` in the document and re-renders.
          document.addEventListener('change', function(e) {
            var t = e.target;
            if (t && t.classList && t.classList.contains('mdtask') &&
                window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mdtask) {
              var line = parseInt(t.getAttribute('data-line'), 10);
              if (!isNaN(line) && line > 0) window.webkit.messageHandlers.mdtask.postMessage(line);
            }
          });
          // Outline navigation: scroll to the heading whose text matches (first match wins).
          window.__scrollToHeading = function(text) {
            var hs = document.querySelectorAll('h1,h2,h3,h4,h5,h6');
            for (var i = 0; i < hs.length; i++) {
              if (hs[i].textContent.trim() === text) { hs[i].scrollIntoView({ block: 'start', behavior: 'smooth' }); return; }
            }
          };
          // Floating "Copy for Telegram": select text in the reader → a button appears → a click copies
          // the selection as Telegram-markdown (bold/italic/code/strike/links kept). The reader has no
          // source markers, so we serialize the selected DOM straight to TG markup. Only wired when
          // hosted in the app (the mdcopy bridge exists); exported standalone HTML omits the button.
          var __NL = String.fromCharCode(10);
          function __tgSer(node) {
            if (node.nodeType === 3) return node.nodeValue;
            if (node.nodeType !== 1 && node.nodeType !== 11) return '';
            var tag = node.nodeName ? node.nodeName.toLowerCase() : '';
            if (tag === 'pre') return __NL + '```' + __NL + (node.textContent || '').trim() + __NL + '```' + __NL;
            if (tag === 'input' || tag === 'button' || tag === 'style' || tag === 'script') return '';
            var inner = '';
            for (var i = 0; i < node.childNodes.length; i++) inner += __tgSer(node.childNodes[i]);
            switch (tag) {
              case 'strong': case 'b': return inner ? '**' + inner + '**' : '';
              case 'em': case 'i': return inner ? '__' + inner + '__' : '';
              case 'del': case 's': case 'strike': return inner ? '~~' + inner + '~~' : '';
              case 'code': return inner ? '`' + inner + '`' : '';
              case 'a': var href = node.getAttribute ? node.getAttribute('href') : ''; return href ? '[' + inner + '](' + href + ')' : inner;
              case 'br': return __NL;
              case 'li': return '- ' + inner.trim() + __NL;
              case 'h1': case 'h2': case 'h3': case 'h4': case 'h5': case 'h6': return __NL + '**' + inner.trim() + '**' + __NL;
              case 'blockquote': return inner.split(__NL).map(function (l) { return l ? '> ' + l : l; }).join(__NL) + __NL;
              case 'p': case 'div': case 'tr': return inner + __NL + __NL;
              case 'ul': case 'ol': return inner + __NL;
              default: return inner;
            }
          }
          function __tgSetup() {
            if (!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mdcopy)) return;
            var btn = document.createElement('button');
            btn.style.cssText = 'position:fixed;z-index:99999;display:none;padding:5px 11px;border:none;border-radius:7px;font:600 12px -apple-system,system-ui,sans-serif;cursor:pointer;background:#15BDEC;color:#fff;box-shadow:0 3px 14px rgba(0,0,0,.35)';
            btn.textContent = '✈ Copy for Telegram';
            document.body.appendChild(btn);
            btn.addEventListener('mousedown', function (e) { e.preventDefault(); });   // keep the selection alive
            function hide() { btn.style.display = 'none'; }
            function place() {
              var sel = window.getSelection();
              if (!sel || sel.isCollapsed || sel.rangeCount === 0 || !sel.toString().trim()) { hide(); return; }
              var r = sel.getRangeAt(0).getBoundingClientRect();
              if (!r || (r.width === 0 && r.height === 0)) { hide(); return; }
              btn.textContent = '✈ Copy for Telegram';
              var top = r.top - 38; if (top < 6) top = r.bottom + 8;
              btn.style.top = top + 'px';
              btn.style.left = Math.max(6, Math.min(r.left, window.innerWidth - 190)) + 'px';
              btn.style.display = 'block';
            }
            btn.addEventListener('click', function () {
              var sel = window.getSelection();
              if (!sel || sel.rangeCount === 0) return;
              var md = __tgSer(sel.getRangeAt(0).cloneContents()).trim();
              if (md) window.webkit.messageHandlers.mdcopy.postMessage(md);
              btn.textContent = '✓ Copied';
              setTimeout(hide, 900);
            });
            document.addEventListener('mouseup', place);
            document.addEventListener('selectionchange', function () {
              var s = window.getSelection();
              if (!s || s.isCollapsed || !s.toString().trim()) hide();
            });
            window.addEventListener('scroll', hide, true);
          }
          if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', __tgSetup);
          else __tgSetup();
          // A click in the reader = "I want to edit here" → the app flips to Source. Links, checkboxes,
          // the floating button, and an active text selection (drag-to-copy) are left to do their own
          // thing. Only wired when hosted in the app; exported standalone HTML ignores it.
          document.addEventListener('click', function (e) {
            if (!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mdedit)) return;
            if (e.target.closest && e.target.closest('a, input, button, label')) return;
            var sel = window.getSelection();
            if (sel && sel.toString().length > 0) return;
            var el = e.target.closest('[data-line]');                        // open Source at the clicked block
            var line = el ? (parseInt(el.getAttribute('data-line'), 10) || 0) : 0;
            window.webkit.messageHandlers.mdedit.postMessage(line);
          });
          window.addEventListener('load', __render);
        </script>
        </head>
        <body>
        <article id="article">\(articleBody(from: markdown))</article>
        </body>
        </html>
        """
    }

    // MARK: - AST -> HTML

    /// ` data-line="N"` for a block's source line (1-indexed) — lets a click in the preview flip to
    /// Source at the same place, and anchors interactive checkboxes. Empty when the range is unknown.
    private static func dataLine(_ markup: Markup) -> String {
        guard let line = markup.range?.lowerBound.line else { return "" }
        return " data-line=\"\(line)\""
    }

    private static func html(for markup: Markup) -> String {
        switch markup {
        case let node as Document:
            return children(node)
        case let node as Heading:
            return "<h\(node.level)\(dataLine(node))>\(children(node))</h\(node.level)>\n"
        case let node as Paragraph:
            return "<p\(dataLine(node))>\(children(node))</p>\n"
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
            // Mermaid fences become a <pre class="mermaid"> the JS renders into a diagram; everything
            // else is <pre><code class="language-…"> ready for highlight.js.
            if node.language?.lowercased() == "mermaid" {
                return "<pre class=\"mermaid\"\(dataLine(node))>\(escape(node.code))</pre>\n"
            }
            let lang = node.language.map { " class=\"language-\(escape($0))\"" } ?? ""
            return "<pre\(dataLine(node))><code\(lang)>\(escape(node.code))</code></pre>\n"
        case let node as Markdown.Table:
            return "<table\(dataLine(node))>\(children(node))</table>\n"
        case let node as Markdown.Table.Head:
            let cells = node.children.map { "<th>\(children($0))</th>" }.joined()
            return "<thead><tr>\(cells)</tr></thead>\n"
        case let node as Markdown.Table.Body:
            return "<tbody>\(children(node))</tbody>\n"
        case let node as Markdown.Table.Row:
            let cells = node.children.map { "<td>\(children($0))</td>" }.joined()
            return "<tr>\(cells)</tr>\n"
        case let node as Markdown.Table.Cell:
            return children(node)
        case let node as Link:
            return "<a href=\"\(safeURL(node.destination ?? ""))\">\(children(node))</a>"
        case let node as Image:
            return "<img src=\"\(safeURL(node.source ?? ""))\" alt=\"\(escape(node.plainText))\">"
        case let node as UnorderedList:
            return "<ul>\n\(children(node))</ul>\n"
        case let node as OrderedList:
            return "<ol>\n\(children(node))</ol>\n"
        case let node as ListItem:
            // `mdtask` checkboxes are interactive in the live preview: a change posts the checkbox's
            // SOURCE line (`data-line`) to the app, which toggles `[ ]`/`[x]` on that exact line — robust
            // against any parser disagreement about task membership. Export still produces a static box.
            let box: String
            let line = node.range?.lowerBound.line ?? 0
            switch node.checkbox {
            case .checked: box = "<input type=\"checkbox\" class=\"mdtask\" data-line=\"\(line)\" checked> "
            case .unchecked: box = "<input type=\"checkbox\" class=\"mdtask\" data-line=\"\(line)\"> "
            case nil: box = ""
            }
            return "<li\(dataLine(node))>\(box)\(children(node))</li>\n"
        case let node as BlockQuote:
            // GFM callout `> [!NOTE]` → styled admonition; otherwise a plain blockquote.
            if let kind = calloutKind(node) {
                return calloutHTML(node, kind: kind)
            }
            return "<blockquote>\n\(children(node))</blockquote>\n"
        case is ThematicBreak:
            return "<hr>\n"
        case is SoftBreak:
            return " "
        case is LineBreak:
            return "<br>\n"
        case let node as InlineHTML:
            return sanitizeRawHTML(node.rawHTML)
        case let node as HTMLBlock:
            return sanitizeRawHTML(node.rawHTML)
        default:
            return children(markup)
        }
    }

    // MARK: - Callouts

    private static let calloutRegex = try! NSRegularExpression(pattern: "^\\s*\\[!([A-Za-z]+)\\]", options: [])

    private static func calloutKind(_ node: BlockQuote) -> String? {
        guard let para = node.children.compactMap({ $0 as? Paragraph }).first else { return nil }
        let text = para.plainText as NSString
        guard let m = calloutRegex.firstMatch(in: para.plainText, range: NSRange(location: 0, length: text.length)),
              m.numberOfRanges > 1 else { return nil }
        return text.substring(with: m.range(at: 1)).uppercased()
    }

    private static func calloutHTML(_ node: BlockQuote, kind: String) -> String {
        var inner = ""
        for (i, child) in node.children.enumerated() {
            if i == 0, let para = child as? Paragraph {
                let body = calloutFirstParagraph(para)
                if !body.isEmpty { inner += "<p>\(body)</p>\n" }
            } else {
                inner += html(for: child)
            }
        }
        let title = kind.prefix(1) + kind.dropFirst().lowercased()
        return "<div class=\"callout callout-\(kind.lowercased())\">"
            + "<p class=\"callout-title\">\(escape(String(title)))</p>\(inner)</div>\n"
    }

    /// Renders a callout's first paragraph with the leading `[!KIND]` marker stripped.
    private static func calloutFirstParagraph(_ para: Paragraph) -> String {
        var out = ""
        var strippedMarker = false
        for child in para.children {
            if !strippedMarker, let text = child as? Text {
                let cleaned = text.string.replacingOccurrences(
                    of: "^\\s*\\[![A-Za-z]+\\]\\s*", with: "", options: .regularExpression)
                out += escape(cleaned)
                strippedMarker = true
            } else if !strippedMarker, child is SoftBreak || child is LineBreak {
                continue   // drop the break that followed a marker on its own line
            } else {
                out += html(for: child)
                strippedMarker = true
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Strips active content from agent-authored raw HTML before it enters the JS-running preview:
    /// `<script>` (DOMParser already won't execute these, but be explicit), embedding tags that can
    /// load remote/active content, inline `on*=` event handlers (which DO fire on inserted nodes,
    /// e.g. `<img onerror>`), and `javascript:` URIs.
    private static func sanitizeRawHTML(_ raw: String) -> String {
        var s = raw
        let patterns = [
            "(?is)<script.*?>.*?</script>",
            "(?is)<script[^>]*/?>",
            "(?is)</?(?:iframe|object|embed|link|meta|base)[^>]*>",
            "(?i)\\son\\w+\\s*=\\s*\"[^\"]*\"",
            "(?i)\\son\\w+\\s*=\\s*'[^']*'",
            "(?i)\\son\\w+\\s*=\\s*[^\\s>]+",
            "(?i)javascript:",
        ]
        for pattern in patterns {
            s = s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return s
    }

    /// Splits leading YAML (`---`) / TOML (`+++`) frontmatter from the body.
    static func splitFrontmatter(_ md: String) -> (frontmatter: String?, body: String) {
        for fence in ["---", "+++"] {
            guard md.hasPrefix(fence) else { continue }
            let lines = md.components(separatedBy: "\n")
            guard lines.first == fence, let close = lines.dropFirst().firstIndex(of: fence) else { continue }
            let fm = lines[1..<close].joined(separator: "\n")
            let body = lines[(close + 1)...].joined(separator: "\n")
            return (fm, body)
        }
        return (nil, md)
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

    /// Escape a link/image URL, neutralizing script-bearing schemes (`javascript:`, `vbscript:`,
    /// `data:text/html`) so `[x](javascript:…)` can't execute in the preview/export. `data:image/…`
    /// and ordinary/relative/mailto/anchor URLs pass through (escaped).
    private static func safeURL(_ raw: String) -> String {
        let probe = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines).joined()   // defeat "java\nscript:" splitting
        if probe.hasPrefix("javascript:") || probe.hasPrefix("vbscript:") || probe.hasPrefix("data:text/html") {
            return "#"
        }
        return escape(raw.trimmingCharacters(in: .whitespacesAndNewlines))
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
        table { border-collapse: collapse; margin: 1em 0; display: block; overflow-x: auto; }
        th, td { border: 1px solid \(border); padding: 6px 10px; text-align: left; }
        th { background: \(codeBg); font-weight: 700; }
        tbody tr:nth-child(even) { background: \(dark ? "#202020" : "#FAFAFA"); }
        .frontmatter { margin: 0 0 1.6em; padding: 10px 14px; border-radius: 8px;
                       background: \(codeBg); border: 1px solid \(border); }
        .frontmatter pre { margin: 0; background: none; padding: 0; font-size: 0.85em; color: \(dim); }
        .callout { margin: 1em 0; padding: 10px 14px 2px; border-radius: 8px; border: 1px solid \(border);
                   border-left: 4px solid \(accent); background: \(codeBg); }
        .callout-title { font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em;
                         font-size: 0.8em; margin: 0 0 0.4em; color: \(accent); }
        .callout-warning, .callout-caution { border-left-color: #E8A33D; } .callout-warning .callout-title, .callout-caution .callout-title { color: #E8A33D; }
        .callout-tip, .callout-success { border-left-color: #4F9A4F; } .callout-tip .callout-title, .callout-success .callout-title { color: #4F9A4F; }
        .callout-important, .callout-danger { border-left-color: #C8402F; } .callout-important .callout-title, .callout-danger .callout-title { color: #C8402F; }
        .mermaid { background: \(dark ? "#202020" : "#FFFFFF"); border-radius: 8px; padding: 12px; text-align: center; }
        .katex { font-size: 1.05em; }
        @media print { body { background: #fff; } article { padding: 0; max-width: none; } }
        """
    }
}
