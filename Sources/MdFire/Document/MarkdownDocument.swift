import AppKit
import Observation
import UniformTypeIdentifiers
import MarkdownCore

/// The open document: the Markdown text plus where it lives on disk. Drives the editor and the
/// File-menu actions (New / Open / Save / Save As). v1 is single-window, single-document.
@Observable
final class MarkdownDocument {
    var text: String
    var fileURL: URL?
    var isDirty: Bool = false

    // MARK: F1 — live reload + change highlighting

    /// What an external on-disk change resulted in, for the reload/conflict banner.
    enum ExternalChange: Equatable {
        case reloaded(changes: Int)   // auto-reloaded; N line-regions changed
        case conflict                 // disk changed but we have unsaved edits (or auto-reload off)
    }

    /// UTF-16 line ranges changed by the last external reload — the editor tints these, decaying.
    var changedRanges: [NSRange] = []
    /// Bumped on every external reload so the editor reloads in place (preserving the viewport)
    /// instead of doing a hard reset (which would jump the scroll to the top).
    var reloadGeneration: Int = 0
    /// Drives the reload/conflict banner; `nil` when there's nothing to show.
    var externalChange: ExternalChange?

    /// The last content we know is on disk — the baseline the change-diff is computed against.
    @ObservationIgnored private var diskBaseline: String = ""
    /// Disk content awaiting a conflict decision (Reload vs Keep Mine).
    @ObservationIgnored private var pendingDiskText: String?
    /// A disk version the user chose to ignore (Keep Mine) — don't re-prompt for the same bytes.
    @ObservationIgnored private var ignoredDiskText: String?
    /// Timestamp of our own last save, so the watcher ignores the event our `write` just caused.
    @ObservationIgnored private var lastSelfWriteAt: Date?
    @ObservationIgnored private var watcher: FileWatcher?
    /// Set by the app so the document can honour the Auto-reload / Show-changes preferences.
    @ObservationIgnored var settings: AppSettings?
    /// The launch welcome/scratch buffer is disposable: opening a real file must not be blocked behind
    /// a "Save changes?" prompt just because the demo text was touched. Cleared once a real file is
    /// opened or saved, after which normal unsaved-changes protection applies.
    @ObservationIgnored private var isPlaceholder = true

    init(text: String = MarkdownDocument.welcome, fileURL: URL? = nil) {
        self.text = text
        self.fileURL = fileURL
        self.diskBaseline = text
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
        isPlaceholder = false   // an explicit new doc is the user's; protect it once edited
        diskBaseline = ""
        changedRanges = []
        externalChange = nil
        watcher = nil
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

    /// Open a file chosen from the workspace sidebar (with the unsaved-changes guard).
    func openFile(at url: URL) {
        guard url != fileURL else { return }
        guard confirmDiscardIfNeeded() else { return }
        load(url)
    }

    func load(_ url: URL) {
        do {
            let loaded = try String(contentsOf: url, encoding: .utf8)
            text = loaded
            fileURL = url
            isDirty = false
            isPlaceholder = false
            diskBaseline = loaded
            changedRanges = []
            externalChange = nil
            pendingDiskText = nil
            ignoredDiskText = nil
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            startWatching()
        } catch {
            present(error, title: "Couldn’t open “\(url.lastPathComponent)”")
        }
    }

    @discardableResult
    func save() -> Bool {
        guard let url = fileURL else { return saveAs() }
        return write(to: url)
    }

    /// Persist now, but only if already backed by a file (no Save panel) — used by F2 checkbox
    /// toggles so a tick survives without an explicit ⌘S.
    func saveIfBacked() { if fileURL != nil { save() } }

    /// Toggle the N-th task checkbox (document order) — driven by clicking a checkbox in the rendered
    /// preview, where the editor isn't available. Writes back to disk if the doc is file-backed.
    func toggleTask(_ index: Int) {
        let tasks = TreeSitterParser().parse(text).filter {
            if case .taskItem = $0.role { return true }; return false
        }
        guard index >= 0, index < tasks.count, let cb = tasks[index].checkboxRange else { return }
        let ns = text as NSString
        guard NSMaxRange(cb) <= ns.length else { return }
        let toggled = ns.substring(with: cb).lowercased().contains("x") ? "[ ]" : "[x]"
        text = ns.replacingCharacters(in: cb, with: toggled)
        isDirty = true
        saveIfBacked()
    }

    /// Checklist completion for the current buffer, cached so the status bar doesn't re-parse on
    /// every redraw — only when the text actually changes.
    @ObservationIgnored private var taskCacheText: String?
    @ObservationIgnored private var taskCacheValue: (done: Int, total: Int)?
    var taskProgress: (done: Int, total: Int)? {
        if taskCacheText == text { return taskCacheValue }
        let (done, total, _, _) = WorkspaceIndex.analyze(text)
        taskCacheText = text
        taskCacheValue = total > 0 ? (done, total) : nil
        return taskCacheValue
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
            lastSelfWriteAt = Date()                 // stamped AFTER the write so the timing window is real
            let wasURL = fileURL
            fileURL = url
            isDirty = false
            isPlaceholder = false
            diskBaseline = text
            ignoredDiskText = nil
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            if wasURL != url { startWatching() }     // first save / Save As → (re)point the watcher
            return true
        } catch {
            present(error, title: "Couldn’t save “\(url.lastPathComponent)”")
            return false
        }
    }

    // MARK: - External-change watching (F1)

    private func startWatching() {
        guard let url = fileURL else { watcher = nil; return }
        watcher = FileWatcher.file(url) { [weak self] in self?.handleExternalChange() }
    }

    /// FSEvents told us the file changed on disk. Decide between silent reload and a conflict banner.
    private func handleExternalChange() {
        if let t = lastSelfWriteAt, Date().timeIntervalSince(t) < 0.6 { return }   // our own save (timing)
        guard let url = fileURL, let disk = try? String(contentsOf: url, encoding: .utf8) else { return }
        // Content-based guards: disk == diskBaseline means it's our own write (or unchanged) regardless
        // of timing; disk == text means the buffer already matches; ignoredDiskText was declined.
        guard disk != diskBaseline, disk != text, disk != ignoredDiskText else { return }

        let autoReload = settings?.autoReload ?? true
        if isDirty || !autoReload {
            // Never clobber unsaved work (or when auto-reload is off): offer the choice.
            pendingDiskText = disk
            externalChange = .conflict
        } else {
            applyReload(disk)
        }
    }

    private func applyReload(_ disk: String) {
        let show = settings?.showChanges ?? true
        changedRanges = show ? DiffRanges.changedLineRanges(from: diskBaseline, to: disk) : []
        text = disk
        diskBaseline = disk
        isDirty = false
        pendingDiskText = nil
        ignoredDiskText = nil
        reloadGeneration += 1
        externalChange = .reloaded(changes: changedRanges.count)
    }

    /// Conflict resolution: take the disk version (discard my unsaved edits).
    func resolveConflictTakeDisk() {
        guard let disk = pendingDiskText else { externalChange = nil; return }
        applyReload(disk)
    }

    /// Conflict resolution: keep my buffer; don't re-prompt for this same disk content. Advance the
    /// diff baseline to the declined disk version so a later reload tints changes since THAT state
    /// (not the now-stale older baseline).
    func resolveConflictKeepMine() {
        if let pending = pendingDiskText { diskBaseline = pending }
        ignoredDiskText = pendingDiskText
        pendingDiskText = nil
        externalChange = nil
    }

    /// Dismiss the transient "reloaded" banner.
    func dismissReloadBanner() {
        if case .reloaded = externalChange { externalChange = nil }
    }

    /// Returns false if the user cancels out of an unsaved-changes prompt.
    private func confirmDiscardIfNeeded() -> Bool {
        guard isDirty, !isPlaceholder else { return true }   // disposable welcome buffer never blocks
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
