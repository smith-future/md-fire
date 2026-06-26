import Foundation

/// An editor formatting command. Inline cases wrap the selection in Markdown markers; `.heading`
/// is block-level — it sets the caret's line to an ATX heading (level 0 clears it back to body).
enum InlineFormat {
    case bold, italic, code, strikethrough
    case heading(Int)

    /// The marker placed on each side of the selection (inline cases only).
    var marker: String {
        switch self {
        case .bold: return "**"
        case .italic: return "_"
        case .code: return "`"
        case .strikethrough: return "~~"
        case .heading: return ""   // block-level, handled separately
        }
    }
}

/// A tiny bridge so the UI / menus can drive the editor without owning it. The TextKitEditor
/// registers its handlers; callers invoke `reveal`/`format`.
@Observable
final class EditorController {
    var revealHandler: ((NSRange) -> Void)?
    var formatHandler: ((InlineFormat) -> Void)?
    var focusHandler: (() -> Void)?

    func reveal(_ range: NSRange) { revealHandler?(range) }
    func format(_ format: InlineFormat) { formatHandler?(format) }
    /// Make the editor the first responder (used by "double-click preview → edit").
    func focus() { focusHandler?() }
}

/// A request to open + select a workspace file, raised by File-menu commands (e.g. ⇧⌘N New File) that
/// can't reach RootView's `selectedFile` @State directly. RootView observes `url` and drives the same
/// open-and-highlight path as the sidebar, so the two entry points stay in sync.
@Observable
final class OpenRequest {
    var url: URL?
}

/// Which editor pane the user last interacted with, so global Format menu commands target the focused
/// pane in split view (not always the primary). Updated by each pane's coordinator on selection change.
@Observable
final class ActivePane {
    var editor: EditorController
    var document: MarkdownDocument
    init(editor: EditorController, document: MarkdownDocument) {
        self.editor = editor
        self.document = document
    }
}
