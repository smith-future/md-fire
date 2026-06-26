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

/// Renders the themed HTML in an offscreen WKWebView, then writes it to a PDF via the async
/// `createPDF` (a synchronous NSPrintOperation with WKWebView deadlocks). Each export is an
/// independent `Job` that owns its own web view / offscreen window / destination URL and is its own
/// navigation delegate, kept alive in `jobs` until it completes — so triggering Export-as-PDF again
/// before the first finishes can't clobber the in-flight one (the old singleton had one slot).
final class PDFExporter {
    static let shared = PDFExporter()
    private var jobs: Set<Job> = []

    func export(markdown: String, title: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (title as NSString).deletingPathExtension + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let html = HTMLRenderer.standaloneHTML(from: markdown, title: title, dark: false)
        let job = Job(html: html, outputURL: url) { [weak self] job in self?.jobs.remove(job) }
        jobs.insert(job)        // retain until it finishes; identity-hashed (NSObject)
        job.start()
    }

    /// One self-contained PDF render; removes itself from its owner when done (success or failure).
    private final class Job: NSObject, WKNavigationDelegate {
        private let html: String
        private let outputURL: URL
        private let onDone: (Job) -> Void
        private var webView: WKWebView!
        private var window: NSWindow?

        init(html: String, outputURL: URL, onDone: @escaping (Job) -> Void) {
            self.html = html
            self.outputURL = outputURL
            self.onDone = onDone
            super.init()
            let frame = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter @72dpi
            let web = WKWebView(frame: frame)
            web.navigationDelegate = self
            // Host in an offscreen window so WebKit lays out and paints before rendering the PDF.
            let win = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentView = web
            win.orderOut(nil)
            webView = web
            window = win
        }

        func start() { webView.loadHTMLString(html, baseURL: nil) }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let url = outputURL
            // Let layout settle a tick, then write the PDF asynchronously (never blocks the app).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                webView.createPDF(configuration: WKPDFConfiguration()) { result in
                    if case .success(let data) = result {
                        try? data.write(to: url)
                        NSWorkspace.shared.activateFileViewerSelecting([url])   // reveal in Finder
                    }
                    self?.finish()
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish() }

        private func finish() {
            window = nil
            onDone(self)
        }
    }
}
