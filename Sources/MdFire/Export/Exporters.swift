import AppKit
import WebKit
import UniformTypeIdentifiers

/// Writes a self-contained, themed `.html` file.
enum HTMLExporter {
    static func export(markdown: String, title: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = (title as NSString).deletingPathExtension + ".html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let html = HTMLRenderer.standaloneHTML(from: markdown, title: title, dark: false)
        do {
            try html.data(using: .utf8)?.write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])   // reveal in Finder
        } catch {}
    }
}

/// Renders the themed HTML in an offscreen WKWebView, then prints it to a paginated PDF via
/// NSPrintOperation (createPDF would emit a single long page).
final class PDFExporter: NSObject, WKNavigationDelegate {
    static let shared = PDFExporter()

    private var webView: WKWebView?
    private var window: NSWindow?
    private var outputURL: URL?

    func export(markdown: String, title: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (title as NSString).deletingPathExtension + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputURL = url

        let html = HTMLRenderer.standaloneHTML(from: markdown, title: title, dark: false)
        let frame = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter @72dpi
        let webView = WKWebView(frame: frame)
        webView.navigationDelegate = self

        // Host in an offscreen window so WebKit lays out and paints before printing.
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        window.orderOut(nil)

        self.webView = webView
        self.window = window
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = outputURL else { return }
        // createPDF is async (no modal run loop) so it never hangs the app, unlike a synchronous
        // NSPrintOperation with WKWebView. Let layout settle a tick first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            webView.createPDF(configuration: WKPDFConfiguration()) { result in
                if case .success(let data) = result {
                    try? data.write(to: url)
                    NSWorkspace.shared.activateFileViewerSelecting([url])   // reveal in Finder
                }
                self?.cleanup()
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { cleanup() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { cleanup() }

    private func cleanup() {
        webView = nil
        window = nil
        outputURL = nil
    }
}
