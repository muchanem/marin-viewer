import Foundation

/// A half-open canonical UTF-8 byte range inside one repository file.
struct SourceRange: Hashable, Sendable {
    let path: String
    let byteRange: Range<Int>

    var start: SourceLocation { SourceLocation(path: path, byteOffset: byteRange.lowerBound) }
    func contains(_ byteOffset: Int) -> Bool { byteRange.contains(byteOffset) }
}

/// How a column value counts code units from the start of its line. SCIP
/// documents declare one of these; Radiology converts at the semantic boundary.
enum ColumnEncoding: String, Sendable, Codable {
    case utf8, utf16, utf32
}

extension SourceBuffer {
    /// Converts a zero-based line and encoding-specific column to a canonical
    /// byte offset. Returns nil when the line does not exist or the column
    /// lands beyond the end of that line, so stale or malformed coordinates
    /// never become fabricated positions. A column that splits a scalar clamps
    /// to the scalar's start. Columns may address the line terminator itself,
    /// which is where half-open ranges ending at end-of-line finish.
    func byteOffset(zeroBasedLine line: Int, column: Int, encoding: ColumnEncoding) -> Int? {
        guard line >= 0, line < lineCount, column >= 0 else { return nil }
        let start = lineStarts[line]
        let end = line + 1 < lineCount ? lineStarts[line + 1] - 1 : data.count
        if column == 0 { return start }
        if encoding == .utf8 {
            guard start + column <= end else { return nil }
            var byte = start + column
            // Clamp into the scalar containing this byte: continuation bytes are 10xxxxxx.
            while byte > start, byte < data.count, data[byte] & 0xC0 == 0x80 { byte -= 1 }
            return byte
        }
        var byte = start
        var units = 0
        var landedInsideScalar = false
        for scalar in String(decoding: data[start..<end], as: UTF8.self).unicodeScalars {
            let width = encoding == .utf16 ? scalar.utf16.count : 1
            if units + width > column { landedInsideScalar = true; break }
            units += width
            byte += scalar.utf8.count
            if units == column { break }
        }
        guard units == column || landedInsideScalar else { return nil }
        return byte
    }

    /// The zero-based line and encoding-specific column of a byte offset, for
    /// matching a caret against externally produced coordinates.
    func position(forByte offset: Int, encoding: ColumnEncoding) -> (line: Int, column: Int) {
        let clamped = max(0, min(offset, data.count))
        let line = self.line(atByte: clamped) - 1
        let start = lineStarts[line]
        if encoding == .utf8 { return (line, clamped - start) }
        var units = 0
        var byte = start
        for scalar in String(decoding: data[start..<clamped], as: UTF8.self).unicodeScalars {
            byte += scalar.utf8.count
            guard byte <= clamped else { break }
            units += encoding == .utf16 ? scalar.utf16.count : 1
        }
        return (line, units)
    }

    /// Text of a one-based line without its terminator.
    func lineText(_ line: Int) -> String {
        let index = max(0, min(line - 1, lineCount - 1))
        let start = lineStarts[index]
        var end = index + 1 < lineCount ? lineStarts[index + 1] - 1 : data.count
        if end > start, data[end - 1] == 0x0D { end -= 1 }
        return String(decoding: data[start..<max(start, end)], as: UTF8.self)
    }

    /// Bytes of a one-based line without its terminator.
    func lineByteRange(_ line: Int) -> Range<Int> {
        let index = max(0, min(line - 1, lineCount - 1))
        let start = lineStarts[index]
        var end = index + 1 < lineCount ? lineStarts[index + 1] - 1 : data.count
        if end > start, data[end - 1] == 0x0D { end -= 1 }
        return start..<max(start, end)
    }

    /// Line text for sidebar display, capped at `limit` bytes on a scalar
    /// boundary with a trailing ellipsis, so generated or minified lines
    /// cannot feed megabytes into a list row.
    func displayLineText(_ line: Int, limit: Int = SourceBuffer.displayLineLimit) -> String {
        let range = lineByteRange(line)
        guard range.count > limit else { return String(decoding: data[range], as: UTF8.self) }
        return String(decoding: data[range.lowerBound..<scalarBoundary(atOrBefore: range.lowerBound + limit, floor: range.lowerBound)], as: UTF8.self) + "…"
    }

    /// Moves a byte offset back to the start of the scalar containing it.
    func scalarBoundary(atOrBefore offset: Int, floor: Int = 0) -> Int {
        var byte = min(offset, data.count)
        while byte > floor, byte < data.count, data[byte] & 0xC0 == 0x80 { byte -= 1 }
        return byte
    }

    static let displayLineLimit = 400
}
