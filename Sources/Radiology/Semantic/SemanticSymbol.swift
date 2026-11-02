import Foundation

/// Identifies one symbol across the index. SCIP `local` symbols are only
/// unique inside their document, so they carry the document path; every other
/// symbol string is global.
struct SemanticSymbolID: Hashable, Sendable, CustomStringConvertible {
    let symbol: String
    let document: String?

    init(symbol: String, document: String) {
        self.symbol = symbol
        self.document = symbol.hasPrefix("local ") ? document : nil
    }

    var isLocal: Bool { document != nil }
    var description: String { document.map { "\(symbol) (local to \($0))" } ?? symbol }
}

struct SemanticSymbol: Sendable, Equatable {
    let id: SemanticSymbolID
    let displayName: String
    let kind: SemanticSymbolKind
    let signature: String
    let documentation: [String]
    let enclosingSymbol: String
    let relationships: [SCIPRelationship]
}

/// Human-readable SCIP `SymbolInformation.Kind` plus a coarse category for icons.
struct SemanticSymbolKind: Sendable, Equatable, Hashable {
    let rawValue: Int
    var name: String { Self.names[rawValue] ?? (rawValue == 0 ? "Symbol" : "Kind \(rawValue)") }

    enum Category: String, Sendable { case type, function, value, module, other }

    var category: Category {
        switch rawValue {
        case 7, 11, 21, 42, 49, 53, 54, 55, 56, 59, 3, 84, 85, 10, 57, 58, 36: .type
        case 17, 26, 9, 18, 45, 66, 67, 68, 69, 70, 71, 72, 74, 76, 80, 25, 34: .function
        case 8, 12, 15, 41, 61, 37, 77, 79, 81, 82, 44, 52, 60, 22: .value
        case 29, 30, 35, 16, 64: .module
        default: .other
        }
    }

    var systemImage: String {
        switch category {
        case .type: "cube"
        case .function: "function"
        case .value: "v.square"
        case .module: "shippingbox"
        case .other: "circle.dotted"
        }
    }

    private static let names: [Int: String] = [
        1: "Array", 2: "Assertion", 3: "Associated Type", 4: "Attribute", 5: "Axiom", 6: "Boolean", 7: "Class",
        8: "Constant", 9: "Constructor", 10: "Data Family", 11: "Enum", 12: "Enum Member", 13: "Event",
        14: "Fact", 15: "Field", 16: "File", 17: "Function", 18: "Getter", 19: "Grammar", 20: "Instance",
        21: "Interface", 22: "Key", 23: "Lang", 24: "Lemma", 25: "Macro", 26: "Method", 27: "Method Receiver",
        28: "Message", 29: "Module", 30: "Namespace", 31: "Null", 32: "Number", 33: "Object", 34: "Operator",
        35: "Package", 36: "Package Object", 37: "Parameter", 38: "Parameter Label", 39: "Pattern",
        40: "Predicate", 41: "Property", 42: "Protocol", 43: "Quasiquoter", 44: "Self Parameter", 45: "Setter",
        46: "Signature", 47: "Subscript", 48: "String", 49: "Struct", 50: "Tactic", 51: "Theorem",
        52: "This Parameter", 53: "Trait", 54: "Type", 55: "Type Alias", 56: "Type Class", 57: "Type Family",
        58: "Type Parameter", 59: "Union", 60: "Value", 61: "Variable", 62: "Contract", 63: "Error",
        64: "Library", 65: "Modifier", 66: "Abstract Method", 67: "Method Specification", 68: "Protocol Method",
        69: "Pure Virtual Method", 70: "Trait Method", 71: "Type Class Method", 72: "Accessor", 73: "Delegate",
        74: "Method Alias", 75: "Singleton Class", 76: "Singleton Method", 77: "Static Data Member",
        78: "Static Event", 79: "Static Field", 80: "Static Method", 81: "Static Property", 82: "Static Variable",
        84: "Extension", 85: "Mixin", 86: "Concept",
    ]
}

/// Minimal reading of the SCIP symbol string grammar: the descriptor list that
/// follows `<scheme> <manager> <package-name> <version>`, with backtick escapes.
enum SCIPSymbolString {
    /// The name of the last descriptor, used when an indexer omits `display_name`.
    static func fallbackName(for symbol: String) -> String {
        if symbol.hasPrefix("local ") { return String(symbol.dropFirst("local ".count)) }
        let descriptors = descriptorText(of: symbol)
        var names: [String] = []
        var current = ""
        var escaped = false
        var index = descriptors.startIndex
        while index < descriptors.endIndex {
            let character = descriptors[index]
            if escaped {
                let next = descriptors.index(after: index)
                if character == "`", next < descriptors.endIndex, descriptors[next] == "`" {
                    current.append("`")
                    index = descriptors.index(after: next)
                    continue
                }
                if character == "`" { escaped = false } else { current.append(character) }
            } else if character == "`" {
                escaped = true
            } else if "/#.:!".contains(character) {
                if !current.isEmpty { names.append(current) }
                current = ""
            } else if character == "(" {
                if !current.isEmpty { names.append(current) }
                current = ""
                // Skip a method disambiguator or parameter body.
                while index < descriptors.endIndex, descriptors[index] != ")" { index = descriptors.index(after: index) }
            } else if character == "[" {
                if !current.isEmpty { names.append(current) }
                current = ""
                // A type-parameter or impl descriptor; its name may itself be a
                // backtick-escaped `[T]`, so brackets inside backticks don't close it.
                var quoted = false
                index = descriptors.index(after: index)
                while index < descriptors.endIndex, quoted || descriptors[index] != "]" {
                    if descriptors[index] == "`" { quoted.toggle() }
                    index = descriptors.index(after: index)
                }
            } else if character != ")" && character != "]" {
                current.append(character)
            }
            index = descriptors.index(after: index)
        }
        if !current.isEmpty { names.append(current) }
        return names.last ?? symbol
    }

    /// `package version` from the symbol header, for naming where an external
    /// symbol comes from. Nil for locals or a placeholder package.
    static func package(of symbol: String) -> String? {
        guard !symbol.hasPrefix("local ") else { return nil }
        let fields = symbol.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: false)
        guard fields.count >= 4 else { return nil }
        // Some indexers put a source URL in the version field; the package
        // name alone is the readable, still-truthful part.
        let parts = [fields[2], fields[3]].filter { !$0.isEmpty && $0 != "." && !$0.contains("://") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Everything after the four space-separated header fields. Double spaces
    /// inside a field are escapes and do not split.
    static func descriptorText(of symbol: String) -> Substring {
        var fields = 0
        var index = symbol.startIndex
        while index < symbol.endIndex, fields < 4 {
            if symbol[index] == " " {
                let next = symbol.index(after: index)
                if next < symbol.endIndex, symbol[next] == " " {
                    index = symbol.index(after: next)
                    continue
                }
                fields += 1
            }
            index = symbol.index(after: index)
        }
        return symbol[index...]
    }
}
