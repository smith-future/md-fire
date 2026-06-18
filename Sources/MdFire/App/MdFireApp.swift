import SwiftUI

/// md-fire — a native macOS markdown editor fusing Typora's live WYSIWYG with
/// iA Writer's focus + typography.
///
/// See docs/PRODUCT.md, docs/ARCHITECTURE.md, docs/UI-DESIGN.md, docs/BUILD-PLAN.md.
@main
struct MdFireApp: App {
    @State private var document = MarkdownDocument()
    @State private var workspace = WorkspaceModel()
    @State private var editor = EditorController()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView(document: document, workspace: workspace, editor: editor, settings: settings)
                .frame(minWidth: 640, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)               // UI-DESIGN §4.1: chromeless
        .defaultSize(width: 1000, height: 720)      // UI-DESIGN §4.1: default window
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { document.newDocument() }
                    .keyboardShortcut("n")
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
            CommandMenu("Format") {
                Button("Bold") { editor.format(.bold) }
                    .keyboardShortcut("b")
                Button("Italic") { editor.format(.italic) }
                    .keyboardShortcut("i")
                Button("Code") { editor.format(.code) }
                    .keyboardShortcut("e")
                Button("Strikethrough") { editor.format(.strikethrough) }
                    .keyboardShortcut("x", modifiers: [.command, .shift])
                Divider()
                Button("Copy for Telegram") { TelegramFormatter.copyToPasteboard(from: document.text) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
    }
}
