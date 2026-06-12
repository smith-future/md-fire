import XCTest
@testable import MarkdownCore

final class RangeMappingTests: XCTestCase {

    func testASCII() {
        let m = RangeMapping("# Hello")
        XCTAssertEqual(m.utf8ByteCount, 7)
        XCTAssertEqual(m.utf16Length, 7)
        XCTAssertEqual(m.nsRange(fromByte: 0, toByte: 1), NSRange(location: 0, length: 1))   // "#"
        XCTAssertEqual(m.nsRange(fromByte: 2, toByte: 7), NSRange(location: 2, length: 5))   // "Hello"
    }

    func testCyrillic() {
        // Each Cyrillic letter is 2 UTF-8 bytes but 1 UTF-16 unit.
        let m = RangeMapping("Привет")
        XCTAssertEqual(m.utf8ByteCount, 12)
        XCTAssertEqual(m.utf16Length, 6)
        XCTAssertEqual(m.utf16Offset(forByte: 6), 3)   // after 3 letters
        XCTAssertEqual(m.nsRange(fromByte: 0, toByte: 12), NSRange(location: 0, length: 6))
    }

    func testEmoji() {
        // "a😀b": a = 1 byte / 1 unit, 😀 = 4 bytes / 2 units (surrogate pair), b = 1 / 1.
        let m = RangeMapping("a😀b")
        XCTAssertEqual(m.utf8ByteCount, 6)
        XCTAssertEqual(m.utf16Length, 4)
        XCTAssertEqual(m.utf16Offset(forByte: 1), 1)   // after 'a'
        XCTAssertEqual(m.utf16Offset(forByte: 5), 3)   // after emoji
        XCTAssertEqual(m.utf16Offset(forByte: 6), 4)   // after 'b'
    }

    func testMixedHeadingBytesVsUnits() {
        // "# 😀 я" -> '#'(1) ' '(1) '😀'(4) ' '(1) 'я'(2) = 9 bytes ; units 1+1+2+1+1 = 6
        let m = RangeMapping("# 😀 я")
        XCTAssertEqual(m.utf8ByteCount, 9)
        XCTAssertEqual(m.utf16Length, 6)
    }

    func testClampsOutOfBounds() {
        let m = RangeMapping("ab")
        XCTAssertEqual(m.utf16Offset(forByte: -5), 0)
        XCTAssertEqual(m.utf16Offset(forByte: 99), 2)
    }
}
