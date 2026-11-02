import Foundation

struct SourceBookmark: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let path: String
    let revision: ReviewRevision?
    let byteOffset: Int
    let line: Int
    let column: Int
    let label: String
    let digest: String
    let anchor: String?
    let precedingLine: String?
    let followingLine: String?

    var location: SourceLocation { SourceLocation(path: path, byteOffset: byteOffset, revision: revision) }
    var isValid: Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
            && byteOffset >= 0 && line > 0 && column >= 0
    }

    static func make(in buffer: SourceBuffer, at byte: Int, label: String, id: UUID = UUID()) -> SourceBookmark {
        let byte = buffer.byteOffset(forUTF16: buffer.utf16Offset(forByte: byte))
        let line = buffer.line(atByte: byte)
        func boundedLine(_ number: Int) -> String? {
            guard number > 0, number <= buffer.lineCount,
                  buffer.lineByteRange(number).count <= SourceBuffer.displayLineLimit else { return nil }
            return buffer.lineText(number)
        }
        let text = boundedLine(line)
        return SourceBookmark(id: id, path: buffer.path, revision: buffer.revision, byteOffset: byte,
                              line: line, column: byte - buffer.lineStarts[line - 1], label: label,
                              digest: ContentDigest.blobID(of: buffer.data),
                              anchor: text?.trimmingCharacters(in: .whitespaces).isEmpty == false ? text : nil,
                              precedingLine: boundedLine(line - 1), followingLine: boundedLine(line + 1))
    }

    /// Exact bytes win; changed files relocate only when their saved line and,
    /// if needed, surrounding lines identify one destination. Never silently
    /// jump an old byte offset into unrelated source after a PR refresh.
    func resolve(in buffer: SourceBuffer) throws -> SourceLocation {
        guard buffer.path == path, buffer.revision == revision else { throw BrowserError.message("The bookmark belongs to a different document.") }
        if ContentDigest.blobID(of: buffer.data) == digest {
            return buffer.location(atByte: buffer.scalarBoundary(atOrBefore: min(byteOffset, buffer.data.count)))
        }
        guard let anchor else { throw BrowserError.message("The bookmarked file changed. Add this location again to update the bookmark.") }
        var matches: [Int] = []
        for number in 1...buffer.lineCount {
            if number.isMultiple(of: 256) { try Task.checkCancellation() }
            if buffer.lineByteRange(number).count <= SourceBuffer.displayLineLimit, buffer.lineText(number) == anchor {
                matches.append(number)
            }
        }
        if matches.count > 1 {
            matches = matches.filter { number in
                let before = number > 1 ? buffer.lineText(number - 1) : nil
                let after = number < buffer.lineCount ? buffer.lineText(number + 1) : nil
                return before == precedingLine && after == followingLine
            }
        }
        guard matches.count == 1, let number = matches.first,
              let byte = buffer.byteOffset(zeroBasedLine: number - 1, column: column, encoding: .utf8) else {
            throw BrowserError.message("The bookmarked line changed or is ambiguous. Add its new location to update the bookmark.")
        }
        return buffer.location(atByte: byte)
    }
}
