import Foundation

/// Maps tree-sitter UTF-8 byte offsets to UTF-16 `NSRange`s (what NSTextStorage / NSAttributedString
/// use). tree-sitter reports byte offsets into the UTF-8 buffer; NSString is UTF-16. Mixing them
/// corrupts ranges for any non-ASCII text (emoji, Cyrillic, CJK), so every byte offset that crosses
/// into the text layer goes through here.
///
/// Boundaries are precomputed once per parse at Unicode scalar boundaries — node byte ranges always
/// land on scalar boundaries, so lookups are exact O(log n) binary searches with no per-call decoding.
public struct RangeMapping {
    /// Cumulative UTF-8 byte offset at the start of each scalar, plus the final total. Strictly increasing.
    private let byteAtScalar: [Int]
    /// Cumulative UTF-16 code-unit offset at the start of each scalar, plus the final total.
    private let utf16AtScalar: [Int]

    public let utf8ByteCount: Int
    public let utf16Length: Int

    public init(_ string: String) {
        var bytes = [0]
        var units = [0]
        bytes.reserveCapacity(string.unicodeScalars.count + 1)
        units.reserveCapacity(string.unicodeScalars.count + 1)
        var b = 0
        var w = 0
        for scalar in string.unicodeScalars {
            let v = scalar.value
            b += v <= 0x7F ? 1 : v <= 0x7FF ? 2 : v <= 0xFFFF ? 3 : 4
            w += v <= 0xFFFF ? 1 : 2
            bytes.append(b)
            units.append(w)
        }
        byteAtScalar = bytes
        utf16AtScalar = units
        utf8ByteCount = b
        utf16Length = w
    }

    /// UTF-16 offset for a UTF-8 byte offset. Byte offsets are clamped to [0, total].
    public func utf16Offset(forByte byte: Int) -> Int {
        if byte <= 0 { return 0 }
        if byte >= utf8ByteCount { return utf16Length }
        // Largest index i with byteAtScalar[i] <= byte.
        var lo = 0
        var hi = byteAtScalar.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if byteAtScalar[mid] <= byte { lo = mid } else { hi = mid - 1 }
        }
        // Exact on a scalar boundary (the expected case for node ranges).
        if byteAtScalar[lo] == byte { return utf16AtScalar[lo] }
        // Defensive: a byte offset mid-scalar (shouldn't happen) maps to that scalar's start.
        return utf16AtScalar[lo]
    }

    /// Convert a half-open UTF-8 byte range to an `NSRange` in UTF-16 space.
    public func nsRange(fromByte start: Int, toByte end: Int) -> NSRange {
        let s = utf16Offset(forByte: start)
        let e = utf16Offset(forByte: max(start, end))
        return NSRange(location: s, length: e - s)
    }

    /// Convenience for tree-sitter's `Range<UInt32>` byte ranges.
    public func nsRange(forByteRange range: Range<UInt32>) -> NSRange {
        nsRange(fromByte: Int(range.lowerBound), toByte: Int(range.upperBound))
    }
}
