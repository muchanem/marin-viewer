import Foundation

/// UTF-8 bytes are canonical. TextKit's UTF-16 offsets are converted here only.
struct SourceBuffer: Sendable {
    let path: String
    let text: String
    let data: Data
    let lineStarts: [Int]
    let utf16LineStarts: [Int]
    let utf16Count: Int
    /// The pull request revision these bytes came from, or nil for the
    /// attached repository's own files. Set by the loader, never by TextKit.
    var revision: ReviewRevision?
    var lineCount: Int { lineStarts.count }

    /// Where this buffer sits: its path in its revision.
    func location(atByte byte: Int) -> SourceLocation {
        SourceLocation(path: path, byteOffset: byte, revision: revision)
    }

    var positionKey: String { SourceLocation.positionKey(path: path, revision: revision) }

    init(path: String, data: Data) throws {
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
            throw BrowserError.message("This file is binary or is not UTF-8 text.")
        }
        self.path = path
        self.text = text
        self.data = data
        var bytes = [0]
        var utf16 = [0]
        var byteOffset = 0
        var utf16Offset = 0
        for scalar in text.unicodeScalars {
            byteOffset += scalar.utf8.count
            utf16Offset += scalar.utf16.count
            if scalar == "\n" { bytes.append(byteOffset); utf16.append(utf16Offset) }
        }
        lineStarts = bytes
        utf16LineStarts = utf16
        utf16Count = utf16Offset
    }

    func line(atByte offset: Int) -> Int { Self.floorIndex(lineStarts, value: max(0, min(offset, data.count))) + 1 }
    func byteOffset(line: Int, column: Int = 0) -> Int {
        let index = max(0, min(line - 1, lineCount - 1))
        let end = index + 1 < lineCount ? lineStarts[index + 1] - 1 : data.count
        return max(lineStarts[index], min(lineStarts[index] + max(0, column), end))
    }

    func utf16Offset(forByte offset: Int) -> Int {
        let clamped = max(0, min(offset, data.count))
        let line = Self.floorIndex(lineStarts, value: clamped)
        var byte = lineStarts[line]
        var utf16 = utf16LineStarts[line]
        let end = line + 1 < lineCount ? lineStarts[line + 1] : data.count
        let lineText = String(decoding: data[lineStarts[line]..<end], as: UTF8.self)
        for scalar in lineText.unicodeScalars {
            if byte + scalar.utf8.count > clamped { break }
            byte += scalar.utf8.count
            utf16 += scalar.utf16.count
            if byte == clamped { break }
        }
        return utf16
    }

    func byteOffset(forUTF16 offset: Int) -> Int {
        let clamped = max(0, min(offset, utf16Count))
        let line = Self.floorIndex(utf16LineStarts, value: clamped)
        var byte = lineStarts[line]
        var utf16 = utf16LineStarts[line]
        let end = line + 1 < lineCount ? lineStarts[line + 1] : data.count
        let lineText = String(decoding: data[lineStarts[line]..<end], as: UTF8.self)
        for scalar in lineText.unicodeScalars {
            if utf16 + scalar.utf16.count > clamped { break }
            byte += scalar.utf8.count
            utf16 += scalar.utf16.count
            if utf16 == clamped { break }
        }
        return byte
    }

    func utf16Range(forByteRange range: Range<Int>) -> NSRange {
        let start = utf16Offset(forByte: range.lowerBound)
        let end = utf16Offset(forByte: range.upperBound)
        return NSRange(location: start, length: max(0, end - start))
    }

    private static func floorIndex(_ offsets: [Int], value: Int) -> Int {
        var low = 0
        var high = offsets.count
        while low < high {
            let middle = (low + high) / 2
            if offsets[middle] <= value { low = middle + 1 } else { high = middle }
        }
        return max(0, low - 1)
    }
}
