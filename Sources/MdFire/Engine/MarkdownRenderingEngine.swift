import AppKit

/// The two editing models. They are NOT two engines — just two `StylePolicy` values over the same
/// parse→map→attribute pipeline (ARCHITECTURE.md §4).
public enum RenderMode: String, CaseIterable, Identifiable {
    case liveWYSIWYG   // Typora: markers hidden, revealed at caret
    case syntaxVisible // iA: markers shown but dimmed

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .liveWYSIWYG: return "Live"
        case .syntaxVisible: return "Source"
        }
    }
}

/// The swap boundary between the native TextKit engine and a possible WKWebView+CodeMirror fallback.
/// Phase 2 implements the TextKit engine; the protocol exists so the rest of the app is engine-agnostic
/// and the fallback can be slotted in if TextKit 2 marker-hiding proves intractable (BUILD-PLAN §2).
public protocol MarkdownRenderingEngine: AnyObject {
    var nsView: NSView { get }
    var text: String { get }
    func setText(_ markdown: String)
    func setMode(_ mode: RenderMode)
    func setTheme(_ theme: Theme)
    var onChange: ((String) -> Void)? { get set }
    var onSelectionChange: ((NSRange) -> Void)? { get set }
}
