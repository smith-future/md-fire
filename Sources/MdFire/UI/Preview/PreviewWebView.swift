import SwiftUI
import WebKit
import AppKit
import Observation

/// Lets the sidebar outline scroll the preview to a heading (the editor is hidden in Preview mode).
@Observable
final class PreviewController {
    @ObservationIgnored var scrollToHeading: ((String) -> Void)?
}

/// The F3 rendered preview pane: a WKWebView fed by `HTMLRenderer.richHTML` (tables, Mermaid,
/// syntax-highlighted code, callouts, KaTeX). A theme change reloads the page; a content change
/// debounces and swaps just the article body via `__setBody`, so the scroll position and already-
/// rendered diagrams survive incremental edits. Reused by the editor+preview split and F5's reader.
struct PreviewWebView: NSViewRepresentable {
    let markdown: String
    let title: String
    let dark: Bool
    var columnChars: Int = 72
    var controller: PreviewController? = nil
    var onToggleTask: ((Int) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.onToggleTask = onToggleTask
        let config = WKWebViewConfiguration()
        // Weak proxy so the user-content controller doesn't retain the coordinator in a cycle.
        config.userContentController.add(WeakMessageHandler(context.coordinator), name: "mdtask")
        config.userContentController.add(WeakMessageHandler(context.coordinator), name: "mdcopy")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        if #available(macOS 12.0, *) { web.underPageBackgroundColor = dark ? .black : .white }
        context.coordinator.web = web
        controller?.scrollToHeading = { [weak coordinator = context.coordinator] title in
            coordinator?.scrollToHeading(title)
        }
        context.coordinator.reload(markdown: markdown, title: title, dark: dark, columnChars: columnChars)
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.onToggleTask = onToggleTask
        context.coordinator.apply(markdown: markdown, title: title, dark: dark, columnChars: columnChars)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var web: WKWebView?
        var onToggleTask: ((Int) -> Void)?
        private var lastDark: Bool?
        private var lastColumnChars: Int?
        private var lastMarkdown = ""
        private var lastTitle = ""
        private var ready = false
        private var pending: String?
        private var debounce: DispatchWorkItem?

        func reload(markdown: String, title: String, dark: Bool, columnChars: Int) {
            debounce?.cancel(); debounce = nil   // a stale body swap must not run against the new page
            pending = nil
            lastDark = dark
            lastColumnChars = columnChars
            lastMarkdown = markdown
            lastTitle = title
            ready = false
            web?.loadHTMLString(HTMLRenderer.richHTML(from: markdown, title: title, dark: dark, columnChars: columnChars), baseURL: nil)
        }

        func apply(markdown: String, title: String, dark: Bool, columnChars: Int) {
            // Theme or column-width change → full reload (both live in the page CSS).
            if dark != lastDark || columnChars != lastColumnChars {
                reload(markdown: markdown, title: title, dark: dark, columnChars: columnChars); return
            }
            guard markdown != lastMarkdown else { return }
            let switchedDoc = title != lastTitle   // a different file, not an incremental edit
            lastMarkdown = markdown
            lastTitle = title
            debounce?.cancel()
            // A document switch should land in lockstep with the sidebar and editor (which reset
            // synchronously) — swap the body NOW and jump to the top. Only incremental typing is
            // debounced, to coalesce a burst of keystrokes into a single body swap.
            guard !switchedDoc else { debounce = nil; pushBody(markdown, resetScroll: true); return }
            let work = DispatchWorkItem { [weak self] in self?.pushBody(markdown) }
            debounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }

        private func pushBody(_ markdown: String, resetScroll: Bool = false) {
            let body = HTMLRenderer.articleBody(from: markdown)
            guard ready, let web else { pending = body; return }
            web.evaluateJavaScript("window.__setBody(\(Self.jsString(body)), \(resetScroll))")
        }

        func scrollToHeading(_ title: String) {
            guard ready, let web else { return }
            web.evaluateJavaScript("window.__scrollToHeading(\(Self.jsString(title)))")
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "mdtask":
                if let index = (message.body as? Int) ?? (message.body as? Double).map(Int.init) {
                    onToggleTask?(index)
                }
            case "mdcopy":
                // The page already serialized the selection to Telegram-markdown — just put it on the
                // pasteboard as plain text (Telegram ignores RTF, auto-formats its own markers on paste).
                if let text = message.body as? String, !text.isEmpty {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                }
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            if let body = pending {
                pending = nil
                webView.evaluateJavaScript("window.__setBody(\(Self.jsString(body)))")
            }
        }

        /// Open externally-clicked links in the browser; never let the pane navigate away from itself.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url, url.scheme == "http" || url.scheme == "https" {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        /// JSON-encode a string into a valid JS string literal for evaluateJavaScript.
        static func jsString(_ s: String) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed])) ?? Data()
            return String(data: data, encoding: .utf8) ?? "\"\""
        }
    }
}

/// Forwards script messages to a weakly-held handler, so the WKUserContentController doesn't retain
/// the coordinator and leak the web view.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
