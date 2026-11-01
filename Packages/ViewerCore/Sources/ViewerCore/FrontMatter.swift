import Foundation

/// A value from the YAML subset that wordbase front matter uses: block maps
/// and block lists (nested, including lists at their key's indent and
/// `- - a` compact lists), plain, single- and double-quoted scalars (also
/// folded over several lines), `|` and `>` block scalars, and the empty
/// flow collections `[]` and `{}` or a flat `[a, b]`. Plain scalars resolve
/// as YAML's core schema does for integers, booleans and null; everything
/// else stays a string. Anchors, tags, flow maps with content and multiple
/// documents are not supported and fail loudly.
public enum FrontMatterValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case string(String)
    case list([FrontMatterValue])
    case map([String: FrontMatterValue])

    public subscript(key: String) -> FrontMatterValue? {
        if case .map(let map) = self { return map[key] }
        return nil
    }

    /// Decodes the value through JSON, so models are ordinary `Codable`
    /// types with snake_case `CodingKeys`.
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [.fragmentsAllowed])
        return try JSONDecoder().decode(type, from: data)
    }

    var jsonObject: Any {
        switch self {
        case .null: NSNull()
        case .bool(let value): value
        case .int(let value): value
        case .string(let value): value
        case .list(let values): values.map(\.jsonObject)
        case .map(let map): map.mapValues(\.jsonObject)
        }
    }
}

public struct FrontMatterError: Error, Equatable, Sendable, CustomStringConvertible {
    /// One-based line within the front matter.
    public let line: Int
    public let message: String

    public var description: String { "front matter line \(line): \(message)" }
}

public enum FrontMatter {
    /// Splits a markdown file into its front matter (between the opening
    /// `---` and the next `---` or `...`) and body. Nil when the file does
    /// not start with `---`.
    public static func split(_ markdown: String) -> (yaml: String, body: String)? {
        var lines = markdown.normalizingLineEndings.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first == "---" else { return nil }
        lines.removeFirst()
        guard let end = lines.firstIndex(where: { $0 == "---" || $0 == "..." }) else { return nil }
        return (lines[..<end].joined(separator: "\n"), lines[(end + 1)...].joined(separator: "\n"))
    }

    /// Parses one YAML document of the supported subset. An empty document
    /// is an empty map.
    public static func parse(_ yaml: String) throws -> FrontMatterValue {
        var parser = Parser(yaml)
        return try parser.document()
    }
}

// MARK: - Parser

private struct Parser {
    struct Line {
        var indent: Int
        var text: String
        let number: Int
    }

    var lines: [Line]
    var index = 0

    init(_ yaml: String) {
        lines = yaml.normalizingLineEndings.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { offset, line in
            let indent = line.prefix { $0 == " " }.count
            return Line(indent: indent, text: String(line.dropFirst(indent)), number: offset + 1)
        }
    }

    mutating func document() throws -> FrontMatterValue {
        skipBlank()
        guard index < lines.count else { return .map([:]) }
        let value = try node(indent: lines[index].indent)
        skipBlank()
        if index < lines.count { throw error("unexpected indentation") }
        return value
    }

    // MARK: Structure

    /// The node whose first line is `lines[index]`, which sits at `indent`.
    mutating func node(indent: Int) throws -> FrontMatterValue {
        let text = lines[index].text
        if Self.isListItem(text) { return try list(indent: indent) }
        if try Self.key(text) != nil { return try map(indent: indent) }
        index += 1
        return try scalar(text, parentIndent: indent - 1)
    }

    mutating func map(indent: Int) throws -> FrontMatterValue {
        var map: [String: FrontMatterValue] = [:]
        while true {
            skipBlank()
            guard index < lines.count, lines[index].indent == indent, !Self.isListItem(lines[index].text) else { break }
            guard let (key, rest) = try Self.key(lines[index].text) else { throw error("expected `key:`") }
            if map[key] != nil { throw error("duplicate key `\(key)`") }
            index += 1
            map[key] = rest.isEmpty ? try child(of: indent, allowsListAtSameIndent: true) : try scalar(rest, parentIndent: indent)
        }
        return .map(map)
    }

    mutating func list(indent: Int) throws -> FrontMatterValue {
        var items: [FrontMatterValue] = []
        while true {
            skipBlank()
            guard index < lines.count, lines[index].indent == indent, Self.isListItem(lines[index].text) else { break }
            let text = lines[index].text
            let rest = text.dropFirst().drop { $0 == " " }
            if rest.isEmpty {
                index += 1
                items.append(try child(of: indent, allowsListAtSameIndent: false))
            } else {
                // Re-read the rest of the line as a node at its own column, so
                // `- id: x` starts a map and `- - a` a nested list.
                let column = indent + text.count - rest.count
                lines[index].indent = column
                lines[index].text = String(rest)
                items.append(try node(indent: column))
            }
        }
        return .list(items)
    }

    /// The value under a `key:` or `-` with nothing after it: a deeper
    /// block, a list at the key's own indent (`key:` then `- a`), or null.
    mutating func child(of indent: Int, allowsListAtSameIndent: Bool) throws -> FrontMatterValue {
        skipBlank()
        guard index < lines.count else { return .null }
        let next = lines[index]
        if next.indent > indent { return try node(indent: next.indent) }
        if allowsListAtSameIndent, next.indent == indent, Self.isListItem(next.text) { return try list(indent: indent) }
        return .null
    }

    // MARK: Scalars

    /// A scalar that starts with `first`; continuation lines are the
    /// following lines indented deeper than `parentIndent`.
    mutating func scalar(_ first: String, parentIndent: Int) throws -> FrontMatterValue {
        if first.hasPrefix("|") || first.hasPrefix(">") { return .string(try blockScalar(first, parentIndent: parentIndent)) }
        if first.hasPrefix("'") || first.hasPrefix("\"") { return .string(try quoted(first, parentIndent: parentIndent)) }
        if first.hasPrefix("[") || first.hasPrefix("{") { return try flow(Self.stripComment(first)) }
        var parts = [Self.stripComment(first)]
        while index < lines.count, lines[index].indent > parentIndent || lines[index].text.isEmpty {
            if lines[index].text.isEmpty {
                // A blank line inside a folded plain scalar is a newline, but a
                // trailing blank line before the next key belongs to no one.
                guard let after = lines[index...].first(where: { !$0.text.isEmpty }), after.indent > parentIndent else { break }
                parts.append("\n")
            } else if lines[index].text.hasPrefix("#") {
                break
            } else if try Self.key(lines[index].text) != nil || Self.isListItem(lines[index].text) {
                throw error("a deeper line after a scalar must continue it, not start a key or list")
            } else {
                parts.append(Self.stripComment(lines[index].text))
            }
            index += 1
        }
        return Self.resolvePlain(Self.fold(parts))
    }

    mutating func quoted(_ first: String, parentIndent: Int) throws -> String {
        let quote = first.first!
        var parts = [first]
        var text = first
        while Self.closingQuote(in: text, quote: quote) == nil {
            guard index < lines.count, lines[index].indent > parentIndent || lines[index].text.isEmpty else {
                throw error("unterminated quoted scalar")
            }
            parts.append(lines[index].text.isEmpty ? "\n" : lines[index].text)
            text = Self.fold(parts)
            index += 1
        }
        let close = Self.closingQuote(in: text, quote: quote)!
        let trailing = Self.stripComment(String(text[text.index(after: close)...]))
        guard trailing.isEmpty else { throw error("text after closing quote") }
        let body = String(text[text.index(after: text.startIndex)..<close])
        return quote == "'" ? body.replacingOccurrences(of: "''", with: "'") : try Self.unescape(body)
    }

    mutating func blockScalar(_ indicator: String, parentIndent: Int) throws -> String {
        let folded = indicator.hasPrefix(">")
        let chomp = indicator.dropFirst().first
        var body: [Line] = []
        while index < lines.count, lines[index].indent > parentIndent || lines[index].text.isEmpty {
            body.append(lines[index])
            index += 1
        }
        while body.last?.text.isEmpty == true { body.removeLast() }
        let blockIndent = body.first { !$0.text.isEmpty }?.indent ?? 0
        let texts = body.map { $0.text.isEmpty ? "" : String(repeating: " ", count: max(0, $0.indent - blockIndent)) + $0.text }
        var value = folded ? Self.fold(texts.map { $0.isEmpty ? "\n" : $0 }) : texts.joined(separator: "\n")
        if chomp != "-", !value.isEmpty { value += "\n" }
        return value
    }

    func flow(_ text: String) throws -> FrontMatterValue {
        if text == "[]" { return .list([]) }
        if text == "{}" { return .map([:]) }
        guard text.hasPrefix("["), text.hasSuffix("]") else { throw error("flow maps are not supported") }
        let inner = text.dropFirst().dropLast()
        guard !inner.contains("["), !inner.contains("{"), !inner.contains("'"), !inner.contains("\"") else {
            throw error("only flat lists of plain scalars are supported in flow style")
        }
        return .list(inner.split(separator: ",").map { Self.resolvePlain($0.trimmingCharacters(in: .whitespaces)) })
    }

    // MARK: Helpers

    mutating func skipBlank() {
        while index < lines.count, lines[index].text.isEmpty || lines[index].text.hasPrefix("#") { index += 1 }
    }

    func error(_ message: String) -> FrontMatterError {
        FrontMatterError(line: index < lines.count ? lines[index].number : lines.count, message: message)
    }

    static func isListItem(_ text: String) -> Bool { text == "-" || text.hasPrefix("- ") }

    /// `key: rest` or `key:`; nil when the line is not a map entry. Plain
    /// keys end at the first `: `, quoted keys at their closing quote.
    static func key(_ text: String) throws -> (String, String)? {
        if let quote = text.first, quote == "'" || quote == "\"" {
            guard let close = closingQuote(in: text, quote: quote) else { return nil }
            let after = text[text.index(after: close)...]
            guard after == ":" || after.hasPrefix(": ") else { return nil }
            let inner = String(text[text.index(after: text.startIndex)..<close])
            let key = quote == "'" ? inner.replacingOccurrences(of: "''", with: "'") : try unescape(inner)
            return (key, after.dropFirst().trimmingCharacters(in: .whitespaces))
        }
        guard let first = text.first, !"[{|>#&*!%@`".contains(first) else { return nil }
        let separator = text.range(of: ": ") ?? (text.hasSuffix(":") ? text.index(before: text.endIndex)..<text.endIndex : nil)
        guard let separator else { return nil }
        let key = text[..<separator.lowerBound]
        guard !key.isEmpty, !key.contains(" #") else { return nil }
        return (String(key), text[separator.upperBound...].trimmingCharacters(in: .whitespaces))
    }

    /// Drops a ` #` comment and trailing spaces from a plain scalar.
    static func stripComment(_ text: String) -> String {
        var text = text
        if text.hasPrefix("#") { return "" }
        if let comment = text.range(of: " #") { text = String(text[..<comment.lowerBound]) }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Joins folded lines with spaces; a `"\n"` part stands for a blank line.
    static func fold(_ parts: [String]) -> String {
        var result = ""
        var lastWasBreak = true
        for part in parts {
            if part == "\n" {
                result += "\n"
                lastWasBreak = true
            } else {
                result += (lastWasBreak ? "" : " ") + part
                lastWasBreak = false
            }
        }
        return result
    }

    static func resolvePlain(_ text: String) -> FrontMatterValue {
        switch text {
        case "", "~", "null", "Null", "NULL": return .null
        case "true", "True", "TRUE": return .bool(true)
        case "false", "False", "FALSE": return .bool(false)
        default:
            let digits = text.hasPrefix("-") || text.hasPrefix("+") ? text.dropFirst() : Substring(text)
            // Leading zeros stay strings, so a numeric short SHA is not mangled.
            let isDecimal = !digits.isEmpty && digits.allSatisfy(\.isASCIIDigit) && (digits.count == 1 || digits.first != "0")
            if isDecimal, let value = Int(text) { return .int(value) }
            return .string(text)
        }
    }

    static func closingQuote(in text: String, quote: Character) -> String.Index? {
        var index = text.index(after: text.startIndex)
        while index < text.endIndex {
            let character = text[index]
            if quote == "\"", character == "\\" {
                index = text.index(index, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                continue
            }
            if character == quote {
                let next = text.index(after: index)
                if quote == "'", next < text.endIndex, text[next] == "'" {
                    index = text.index(after: next)
                    continue
                }
                return index
            }
            index = text.index(after: index)
        }
        return nil
    }

    static func unescape(_ text: String) throws -> String {
        var result = ""
        var characters = text[...]
        while let character = characters.popFirst() {
            guard character == "\\", let escape = characters.popFirst() else {
                result.append(character)
                continue
            }
            switch escape {
            case "n": result.append("\n")
            case "t": result.append("\t")
            case "r": result.append("\r")
            case "0": result.append("\0")
            case "\"", "\\", "/", " ": result.append(escape)
            case "u", "x", "U":
                let width = escape == "x" ? 2 : escape == "u" ? 4 : 8
                guard let code = UInt32(characters.prefix(width), radix: 16), let scalar = Unicode.Scalar(code) else {
                    throw FrontMatterError(line: 0, message: "bad escape in double-quoted scalar")
                }
                result.unicodeScalars.append(scalar)
                characters = characters.dropFirst(width)
            default:
                throw FrontMatterError(line: 0, message: "unsupported escape \\\(escape)")
            }
        }
        return result
    }
}

extension String {
    /// `\r\n` is one `Character` in Swift, so a split on `"\n"` would miss
    /// it; normalize first.
    var normalizingLineEndings: String { replacingOccurrences(of: "\r\n", with: "\n") }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
