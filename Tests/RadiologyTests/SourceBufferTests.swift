import Foundation
import Testing
@testable import Radiology

struct SourceBufferTests {
    @Test func coordinatesHandleEmojiCombiningMarksAndCRLF() throws {
        let text = "a🙂é\r\n漢字 e\u{301}\n"
        let buffer = try SourceBuffer(path: "unicode.swift", data: Data(text.utf8))
        #expect(buffer.lineStarts == [0, 9, 20])
        #expect(buffer.utf16LineStarts == [0, 6, 12])
        #expect(buffer.lineCount == 3)
        #expect(buffer.utf16Offset(forByte: 5) == 3)
        #expect(buffer.byteOffset(forUTF16: 3) == 5)
        #expect(buffer.utf16Offset(forByte: 3) == 1) // inside the emoji clamps to its start
        #expect(buffer.byteOffset(forUTF16: 2) == 1)
        #expect(buffer.byteOffset(line: 2, column: 3) == 12)
        #expect(buffer.line(atByte: 12) == 2)
        for index in text.indices {
            let bytes = text[..<index].utf8.count
            let utf16 = text[..<index].utf16.count
            #expect(buffer.utf16Offset(forByte: bytes) == utf16)
            #expect(buffer.byteOffset(forUTF16: utf16) == bytes)
        }
        #expect(buffer.utf16Offset(forByte: buffer.data.count) == text.utf16.count)
    }

    @Test func emptySourceAndOutOfBoundsLocations() throws {
        let empty = try SourceBuffer(path: "empty", data: Data())
        #expect(empty.lineCount == 1)
        #expect(empty.byteOffset(line: 100) == 0)
        #expect(empty.utf16Offset(forByte: -4) == 0)
        let source = try SourceBuffer(path: "f", data: Data("abc\nxyz".utf8))
        #expect(source.byteOffset(line: 1, column: 200) == 3)
        #expect(source.byteOffset(line: 100) == 4)
        #expect(source.byteOffset(forUTF16: 100) == 7)
    }

    @Test func binaryAndInvalidUTF8AreRejected() {
        #expect(throws: BrowserError.self) { try SourceBuffer(path: "binary", data: Data([0, 1, 2])) }
        #expect(throws: BrowserError.self) { try SourceBuffer(path: "invalid", data: Data([0xff])) }
    }

    @Test func convertsCanonicalByteRangesToTextKitRanges() throws {
        let source = try SourceBuffer(path: "unicode.swift", data: Data("a🩻胸z".utf8))
        let start = "a".utf8.count
        let end = start + "🩻胸".utf8.count
        #expect(source.utf16Range(forByteRange: start..<end) == NSRange(location: 1, length: 3))
    }
}
