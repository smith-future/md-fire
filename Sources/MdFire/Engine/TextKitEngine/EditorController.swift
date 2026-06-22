import Foundation

/// Inline formatting that wraps the selection in Markdown markers.
enum InlineFormat {
    case bold, italic, code, strikethrough

    /// The marker placed on each side of the selection.
    var marker: String {
        switch self {
        case .bold: return "**"
        case .italic: return "_"
        case .code: return "`"
        case .strikethrough: return "~~"
        }
    }
}

/// A tiny bridge so the UI / menus can drive the editor without owning it. The TextKitEditor
/// registers its handlers; callers invoke `reveal`/`format`.
@Observable
final class EditorController {
    var revealHandler: ((NSRange) -> Void)?
    var formatHandler: ((InlineFormat) -> Void)?

    func reveal(_ range: NSRange) { revealHandler?(range) }
    func format(_ format: InlineFormat) { formatHandler?(format) }
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
