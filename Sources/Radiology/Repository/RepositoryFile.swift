import Foundation

struct RepositoryFile: Identifiable, Hashable, Sendable {
    let path: String
    var id: String { path }
    var name: String { URL(filePath: path).lastPathComponent }

    /// The parsed grammar's name when one is registered, otherwise a plain
    /// label for file kinds Radiology shows as text.
    var language: String {
        if let parsed = SourceLanguageRegistry.language(for: path) { return parsed.displayName }
        return switch URL(filePath: path).pathExtension.lowercased() {
        case "c", "h": "C"
        case "cpp", "cc", "cxx", "hpp": "C++"
        case "m": "Objective-C"
        case "java": "Java"
        case "rb": "Ruby"
        case "sh", "bash", "zsh": "Shell"
        case "md", "markdown": "Markdown"
        case "json": "JSON"
        case "yml", "yaml": "YAML"
        case "toml": "TOML"
        case "html": "HTML"
        case "css": "CSS"
        case "sql": "SQL"
        default: "Plain text"
        }
    }

    /// True when a Tree-sitter grammar is registered for this file.
    var isParsed: Bool { SourceLanguageRegistry.language(for: path) != nil }
}
