import Foundation
import NaturalLanguage

/// Focus Mode scope (iA Writer): which span around the caret stays bright while the rest dims.
public enum FocusScope: String, CaseIterable, Sendable {
    case off
    case sentence
    case line
    case paragraph

    public var dims: Bool { self != .off }

    public var label: String {
        switch self {
        case .off: return "Off"
        case .sentence: return "Sentence"
        case .line: return "Line"
        case .paragraph: return "Paragraph"
        }
    }
}

/// Computes the active (bright) range for Focus Mode. Pure + testable — sentence boundaries come from
/// `NLTokenizer`, paragraph from `NSString.paragraphRange`. Returns nil when nothing should dim.
public enum FocusRange {
    public static func active(in text: String, caret: Int, scope: FocusScope) -> NSRange? {
        let ns = text as NSString
        let length = ns.length
        guard length > 0, scope.dims else { return nil }
        let caret = max(0, min(caret, length))

        switch scope {
        case .paragraph, .line:
            // .line falls back to the paragraph here; the engine overrides it with the actual
            // visual line from TextKit 2 layout (the pure layer has no layout information).
            return ns.paragraphRange(for: NSRange(location: caret, length: 0))
        case .sentence:
            return sentenceRange(ns: ns, caret: caret)
        case .off:
            return nil
        }
    }

    /// Sentence containing the caret. Tokenization is restricted to the caret's paragraph for speed;
    /// falls back to the whole paragraph if no sentence token contains the caret.
    private static func sentenceRange(ns: NSString, caret: Int) -> NSRange {
        let para = ns.paragraphRange(for: NSRange(location: caret, length: 0))
        let substring = ns.substring(with: para)
        let localCaret = caret - para.location

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = substring

        var result = para
        tokenizer.enumerateTokens(in: substring.startIndex..<substring.endIndex) { range, _ in
            let local = NSRange(range, in: substring)
            if localCaret >= local.location && localCaret <= local.location + local.length {
                result = NSRange(location: para.location + local.location, length: local.length)
                return false
            }
            return true
        }
        return result
    }
}
