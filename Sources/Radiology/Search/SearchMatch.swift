import Foundation

struct SearchMatch: Identifiable, Sendable {
    let path: String
    let line: Int
    let column: Int
    let byteOffset: Int
    let preview: String
    var id: String { "\(path):\(byteOffset)" }
    var location: SourceLocation { SourceLocation(path: path, byteOffset: byteOffset) }

    static func decode(_ data: Data) throws -> [SearchMatch] {
        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              event["type"] as? String == "match",
              let payload = event["data"] as? [String: Any],
              let pathValue = payload["path"] as? [String: String],
              let linesValue = payload["lines"] as? [String: String],
              let path = decodeText(pathValue), let preview = decodeText(linesValue),
              let line = payload["line_number"] as? Int,
              let offset = payload["absolute_offset"] as? Int,
              let matches = payload["submatches"] as? [[String: Any]] else { return [] }
        return matches.compactMap { match in
            guard let start = match["start"] as? Int else { return nil }
            return SearchMatch(path: path.hasPrefix("./") ? String(path.dropFirst(2)) : path, line: line, column: start + 1, byteOffset: offset + start, preview: preview.trimmingCharacters(in: .newlines))
        }
    }

    private static func decodeText(_ value: [String: String]) -> String? {
        if let text = value["text"] { return text }
        if let base64 = value["bytes"], let data = Data(base64Encoded: base64) { return String(data: data, encoding: .utf8) }
        return nil
    }
}
