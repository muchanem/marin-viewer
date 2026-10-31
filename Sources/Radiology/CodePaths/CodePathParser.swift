import Foundation

enum CodePathParser {
    static let maximumBytes = 2 * 1024 * 1024

    static func parse(_ text: String) throws -> CodePath {
        guard text.utf8.count <= maximumBytes else { throw BrowserError.message("Code paths must be no larger than 2 MB.") }
        let normalized = text.replacing("\r\n", with: "\n").replacing("\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        let title = String(lines.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
        guard !title.isEmpty else { throw BrowserError.message("Line 1: enter a title for this code path.") }
        var steps: [CodePathStep] = []
        for (offset, line) in lines.dropFirst().enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let fields = fields(in: line)
            guard fields.count == 3 else {
                throw BrowserError.message("Line \(offset + 2): expected file:function:description.")
            }
            let step = CodePathStep(id: UUID(), path: fields[0],
                                    function: fields[1], description: fields[2])
            guard step.isValid else {
                throw BrowserError.message("Line \(offset + 2): use a repository-relative file path and nonempty function and description.")
            }
            steps.append(step)
        }
        guard !steps.isEmpty else { throw BrowserError.message("Add at least one file:function:description after the title.") }
        return CodePath(id: UUID(), title: title, steps: steps)
    }

    /// Only the first two unescaped colons delimit fields. The description
    /// is freeform; escape colons/backslashes in file and function as \: / \\.
    private static func fields(in line: Substring) -> [String] {
        var fields: [String] = []
        var field = ""
        var cursor = line.startIndex
        while cursor < line.endIndex {
            let character = line[cursor]
            let next = line.index(after: cursor)
            if fields.count < 2, character == "\\", next < line.endIndex,
               line[next] == ":" || line[next] == "\\" {
                field.append(line[next])
                cursor = line.index(after: next)
                continue
            }
            if character == ":", fields.count < 2 {
                fields.append(field.trimmingCharacters(in: .whitespaces))
                field = ""
            } else { field.append(character) }
            cursor = next
        }
        fields.append(field.trimmingCharacters(in: .whitespaces))
        return fields
    }
}
