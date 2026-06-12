import AppKit
import Observation
import UniformTypeIdentifiers

/// The open document: the Markdown text plus where it lives on disk. Drives the editor and the
/// File-menu actions (New / Open / Save / Save As). v1 is single-window, single-document.
@Observable
final class MarkdownDocument {
    var text: String
    var fileURL: URL?
    var isDirty: Bool = false

    init(text: String = MarkdownDocument.welcome, fileURL: URL? = nil) {
        self.text = text
        self.fileURL = fileURL
    }

    var displayName: String {
        fileURL?.lastPathComponent ?? "Untitled"
    }

    /// Called by the editor on user edits.
    func userEdited(_ newText: String) {
        text = newText
        isDirty = true
    }

    func newDocument() {
        guard confirmDiscardIfNeeded() else { return }
        text = ""
        fileURL = nil
        isDirty = false
    }

    func open() {
        guard confirmDiscardIfNeeded() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.markdownTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    func load(_ url: URL) {
        do {
            text = try String(contentsOf: url, encoding: .utf8)
            fileURL = url
            isDirty = false
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch {
            present(error, title: "Couldn’t open “\(url.lastPathComponent)”")
        }
    }

    @discardableResult
    func save() -> Bool {
        guard let url = fileURL else { return saveAs() }
        return write(to: url)
    }

    @discardableResult
    func saveAs() -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = Self.markdownTypes
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "Untitled.md"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return write(to: url)
    }

    @discardableResult
    private func write(to url: URL) -> Bool {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            fileURL = url
            isDirty = false
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            return true
        } catch {
            present(error, title: "Couldn’t save “\(url.lastPathComponent)”")
            return false
        }
    }

    /// Returns false if the user cancels out of an unsaved-changes prompt.
    private func confirmDiscardIfNeeded() -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to “\(displayName)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertSecondButtonReturn: return true        // discard
        default: return false                              // cancel
        }
    }

    private func present(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    static let markdownTypes: [UTType] = {
        let exts = ["md", "markdown", "mdown", "txt"].compactMap { UTType(filenameExtension: $0) }
        return exts.isEmpty ? [.plainText] : exts + [.plainText]
    }()

    static let welcome = """
    # md-fire

    A native macOS editor: **Typora** live preview × _iA Writer_ focus.

    Open a file with **⌘O**, or just start writing. Toggle **Source / Live** in the status bar —
    the text never changes, only how `markers` are shown.

    - [x] tree-sitter parser
    - [x] native gap-free WYSIWYG
    - [ ] focus & typewriter mode
    """
}
