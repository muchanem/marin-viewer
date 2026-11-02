import Foundation

/// The native catalog reads typed root settings; seL4's nested recipe is read
/// by Python's standard tomllib. Root values use strings, integers and string
/// arrays. Unsupported root syntax is an error, never a guessed default.
enum PersonalityTOML {
    static func rootValues(_ text: String) throws -> [String: String] {
        var values: [String: String] = [:]
        var pending = ""
        for line in text.components(separatedBy: .newlines) {
            var clean = "", quote: Character?, escaped = false
            for character in line {
                if let active = quote {
                    clean.append(character)
                    if escaped { escaped = false }
                    else if character == "\\" && active == "\"" { escaped = true }
                    else if character == active { quote = nil }
                } else if character == "#" { break }
                else {
                    clean.append(character)
                    if character == "\"" || character == "'" { quote = character }
                }
            }
            guard quote == nil else { throw BrowserError.message("Personality root strings must fit on one line.") }
            clean = clean.trimmingCharacters(in: .whitespaces)
            if pending.isEmpty && clean.hasPrefix("[") { break }
            pending += clean
            if pending.isEmpty { continue }
            guard let separator = pending.firstIndex(of: "=") else { throw BrowserError.message("Expected key = value in personality settings.") }
            let key = pending[..<separator].trimmingCharacters(in: .whitespaces)
            let value = pending[pending.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("[") && !value.hasSuffix("]") { continue }
            guard values[key] == nil else { throw BrowserError.message("Duplicate personality setting: \(key)") }
            values[key] = value
            pending = ""
        }
        guard pending.isEmpty else { throw BrowserError.message("Unterminated personality setting.") }
        return values
    }

    static func string(_ value: String?) throws -> String {
        guard let value else { throw BrowserError.message("A required personality setting is missing.") }
        if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
            let contents = String(value.dropFirst().dropLast())
            guard !contents.contains("'") else { throw BrowserError.message("Invalid literal string in personality settings.") }
            return contents
        }
        guard let data = value.data(using: .utf8), let string = try? JSONDecoder().decode(String.self, from: data) else {
            throw BrowserError.message("Expected a quoted personality setting, found: \(value)")
        }
        return string
    }

    static func strings(_ value: String?) throws -> [String] {
        guard let value, value.hasPrefix("["), value.hasSuffix("]") else { throw BrowserError.message("Expected a string array in personality settings.") }
        var items: [String] = [], item = "", quote: Character?, escaped = false
        for character in value.dropFirst().dropLast() {
            if let active = quote {
                item.append(character)
                if escaped { escaped = false }
                else if character == "\\" && active == "\"" { escaped = true }
                else if character == active { quote = nil }
            } else if character == "," {
                items.append(try string(item.trimmingCharacters(in: .whitespaces)))
                item = ""
            } else {
                item.append(character)
                if character == "\"" || character == "'" { quote = character }
            }
        }
        guard quote == nil else { throw BrowserError.message("Unterminated string in personality settings.") }
        if !item.trimmingCharacters(in: .whitespaces).isEmpty { items.append(try string(item.trimmingCharacters(in: .whitespaces))) }
        return items
    }
}
