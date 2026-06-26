import SwiftUI

/// md-fire — a native macOS markdown editor fusing Typora's live WYSIWYG with
/// iA Writer's focus + typography.
///
/// See docs/PRODUCT.md, docs/ARCHITECTURE.md, docs/UI-DESIGN.md, docs/BUILD-PLAN.md.
@main
struct MdFireApp: App {
    @State private var document: MarkdownDocument
    @State private var splitDocument: MarkdownDocument
    @State private var workspace = WorkspaceModel()
    @State private var editor: EditorController
    @State private var splitEditor: EditorController
    @State private var settings: AppSettings
    @State private var palette = PaletteModel()
    @State private var activePane: ActivePane
    @State private var openRequest = OpenRequest()

    init() {
        let settings = AppSettings()
        let document = MarkdownDocument()
        let splitDocument = MarkdownDocument(text: "")
        document.settings = settings           // so the document honours Auto-reload / Show-changes
        splitDocument.settings = settings
        let editor = EditorController()
        let splitEditor = EditorController()
        _settings = State(initialValue: settings)
        _document = State(initialValue: document)
        _splitDocument = State(initialValue: splitDocument)
        _editor = State(initialValue: editor)
        _splitEditor = State(initialValue: splitEditor)
        _activePane = State(initialValue: ActivePane(editor: editor, document: document))
    }

    var body: some Scene {
        WindowGroup {
            RootView(document: document, splitDocument: splitDocument, workspace: workspace,
                     editor: editor, splitEditor: splitEditor, settings: settings,
                     palette: palette, activePane: activePane, openRequest: openRequest)
                .frame(minWidth: 640, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)               // UI-DESIGN §4.1: chromeless
        .defaultSize(width: 1000, height: 720)      // UI-DESIGN §4.1: default window
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { document.newDocument() }
                    .keyboardShortcut("n")
                Button("New File…") {
                    DispatchQueue.main.async {
                        if let url = workspace.createFileInteractively() { openRequest.url = url }
                    }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(workspace.root == nil)
                Button("Open…") { document.open() }
                    .keyboardShortcut("o")
                Button("Open Folder…") { workspace.openFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { document.save() }
                    .keyboardShortcut("s")
                Button("Save As…") { document.saveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .importExport) {
                Button("Export as HTML…") {
                    HTMLExporter.export(markdown: document.text, title: document.displayName)
                }
                Button("Export as PDF…") {
                    PDFExporter.shared.export(markdown: document.text, title: document.displayName)
                }
            }
            CommandGroup(replacing: .printItem) {}   // free ⌘P for Go to File
            CommandMenu("Navigate") {
                Button("Go to File…") { palette.openFiles() }
                    .keyboardShortcut("p")
                Button("Find in Workspace…") { palette.openSearch() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Divider()
                Button(settings.previewVisible ? "Hide Preview" : "Show Preview") {
                    settings.previewVisible.toggle()
                }
                .keyboardShortcut("p", modifiers: [.command, .control])
            }
            CommandMenu("Format") {
                // Route to the focused pane (primary unless the split pane was last interacted with).
                Button("Bold") { activePane.editor.format(.bold) }
                    .keyboardShortcut("b")
                Button("Italic") { activePane.editor.format(.italic) }
                    .keyboardShortcut("i")
                Button("Code") { activePane.editor.format(.code) }
                    .keyboardShortcut("e")
                Button("Strikethrough") { activePane.editor.format(.strikethrough) }
                    .keyboardShortcut("x", modifiers: [.command, .shift])
                Divider()
                Button("Heading 1") { activePane.editor.format(.heading(1)) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Heading 2") { activePane.editor.format(.heading(2)) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Heading 3") { activePane.editor.format(.heading(3)) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Body Text") { activePane.editor.format(.heading(0)) }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
                Button("Copy for Telegram") { TelegramFormatter.copyToPasteboard(from: activePane.document.text) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
    }
}
