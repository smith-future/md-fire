import Foundation

/// Computes which **UTF-16 NSRanges** of a new text changed relative to a previous version — the
/// substrate of F1's "highlight what the agent just rewrote". Line-level granularity (a modified or
/// newly inserted line is flagged in full), which matches the cockpit's "these lines were rewritten"
/// story and is cheap. Lives in MarkdownCore so it's unit-testable without an app host and — crucially
/// — emits UTF-16 code-unit ranges (the same convention as NSTextStorage and the parser), so offsets
/// stay aligned on Cyrillic/emoji.
public enum DiffRanges {

    /// Line-level changed regions of `new` relative to `old`, as UTF-16 NSRanges into `new`.
    /// Inserted or modified lines are returned; pure deletions don't map to a range in `new`.
    /// Contiguous changed lines are merged into a single span (bridging the newline between them).
    public static func changedLineRanges(from old: String, to new: String) -> [NSRange] {
        guard old != new else { return [] }
        let oldLines = lines(of: old).map(\.text)
        let newSpans = lines(of: new)
        let diff = newSpans.map(\.text).difference(from: oldLines)

        var changedIndices = Set<Int>()
        for change in diff {
            if case let .insert(offset, _, _) = change { changedIndices.insert(offset) }
        }
        let ranges = changedIndices.sorted().compactMap { idx -> NSRange? in
            idx < newSpans.count ? newSpans[idx].range : nil
        }
        return merge(ranges)
    }

    // MARK: - Internals

    /// Splits into lines, returning each line's UTF-16 NSRange (without its trailing newline) and text.
    static func lines(of string: String) -> [(range: NSRange, text: String)] {
        let ns = string as NSString
        let length = ns.length
        var result: [(NSRange, String)] = []
        var start = 0
        var i = 0
        while i < length {
            if ns.character(at: i) == 10 {   // '\n'
                let r = NSRange(location: start, length: i - start)
                result.append((r, ns.substring(with: r)))
                start = i + 1
            }
            i += 1
        }
        let tail = NSRange(location: start, length: length - start)
        result.append((tail, ns.substring(with: tail)))
        return result
    }

    /// Merges sorted ranges, joining any whose gap is ≤1 code unit (the newline between adjacent lines).
    static func merge(_ ranges: [NSRange]) -> [NSRange] {
        guard !ranges.isEmpty else { return [] }
        var out: [NSRange] = [ranges[0]]
        for r in ranges.dropFirst() {
            let last = out[out.count - 1]
            if r.location <= NSMaxRange(last) + 1 {
                let end = max(NSMaxRange(last), NSMaxRange(r))
                out[out.count - 1] = NSRange(location: last.location, length: end - last.location)
            } else {
                out.append(r)
            }
        }
        return out
    }
}
