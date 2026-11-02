import Foundation

/// A small, bounded excerpt of real source starting at a definition. It is
/// display data only: never a navigation target and never reconstructed from
/// SCIP metadata.
struct DefinitionPreview: Sendable, Equatable {
    let path: String
    let lines: [SnippetLine]
    /// More source follows the excerpt.
    let isTruncated: Bool

    var startLine: Int { lines.first?.number ?? 1 }

    static let maxLines = 12

    /// The end of the Tree-sitter declaration whose name holds the definition
    /// byte: an exact name start first, else the narrowest name containing it.
    static func declarationEnd(at byte: Int, in syntax: SyntaxSnapshot?) -> Int? {
        guard let symbols = syntax?.symbols else { return nil }
        if let exact = symbols.filter({ $0.selectionByteRange.lowerBound == byte }).min(by: { $0.byteRange.count < $1.byteRange.count }) {
            return exact.byteRange.upperBound
        }
        return symbols.filter { $0.selectionByteRange.contains(byte) }
            .min { $0.byteRange.count < $1.byteRange.count }?.byteRange.upperBound
    }

    /// Starts on the definition's line. With a known declaration end (the
    /// current file's Tree-sitter structure), stops there; otherwise stops at
    /// the first blank line after the first, so a preview of another file does
    /// not run into the next item. Always capped at `maxLines`.
    static func make(buffer: SourceBuffer, startByte: Int, declarationEnd: Int?, maxLines: Int) -> DefinitionPreview {
        let first = buffer.line(atByte: startByte)
        let last = declarationEnd.map { buffer.line(atByte: max(startByte, $0 - 1)) } ?? buffer.lineCount
        var lines: [SnippetLine] = []
        var number = first
        while number <= last, lines.count < maxLines {
            let text = buffer.displayLineText(number)
            if declarationEnd == nil, number > first, text.allSatisfy(\.isWhitespace) { break }
            lines.append(SnippetLine(number: number, text: text))
            number += 1
        }
        let truncated = number <= last && (declarationEnd != nil || !buffer.lineByteRange(number).allSatisfy {
            buffer.data[$0] == 0x20 || buffer.data[$0] == 0x09
        })
        return DefinitionPreview(path: buffer.path, lines: lines, isTruncated: truncated && lines.count == maxLines)
    }
}
