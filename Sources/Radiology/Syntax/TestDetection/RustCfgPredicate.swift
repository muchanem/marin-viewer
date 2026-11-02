import Foundation
import SwiftTreeSitter

/// A Rust `cfg` predicate read from an attribute's `token_tree`, evaluated in
/// three-valued logic. Only `test`/`doctest` have known values; features,
/// targets, and anything unparsed stay unknown, so production-reachable code
/// is never called test-only.
indirect enum RustCfgPredicate: Equatable {
    case flag(String)
    case keyValue(String)
    case all([RustCfgPredicate])
    case any([RustCfgPredicate])
    case not(RustCfgPredicate)
    case unparsed

    enum Truth: Equatable {
        case yes, no, unknown

        var negated: Truth {
            switch self {
            case .yes: .no
            case .no: .yes
            case .unknown: .unknown
            }
        }
    }

    /// Compiled only for tests: false in every build without `test`, and
    /// not false in every build (`cfg(any())` is dead code, not test code).
    var isTestOnly: Bool {
        evaluate(testing: false) == .no && evaluate(testing: true) != .no
    }

    func evaluate(testing: Bool) -> Truth {
        switch self {
        case .flag(let name):
            guard name == "test" || name == "doctest" else { return .unknown }
            return testing ? (name == "test" ? .yes : .unknown) : .no
        case .keyValue, .unparsed:
            return .unknown
        case .all(let items):
            let values = items.map { $0.evaluate(testing: testing) }
            if values.contains(.no) { return .no }
            return values.allSatisfy { $0 == .yes } ? .yes : .unknown
        case .any(let items):
            let values = items.map { $0.evaluate(testing: testing) }
            if values.contains(.yes) { return .yes }
            return values.allSatisfy { $0 == .no } ? .no : .unknown
        case .not(let item):
            return item.evaluate(testing: testing).negated
        }
    }

    /// Parses the single predicate inside `cfg(...)`'s argument tree.
    static func parse(arguments tree: Node, data: Data) -> RustCfgPredicate {
        let items = list(in: tree, data: data)
        return items.count == 1 ? items[0] : .unparsed
    }

    /// Comma-separated predicates between a token tree's delimiters.
    private static func list(in tree: Node, data: Data) -> [RustCfgPredicate] {
        let tokens = tree.childNodes(namedOnly: false)
        guard tokens.count >= 2 else { return [] }
        var groups: [[Node]] = [[]]
        for token in tokens.dropFirst().dropLast() {
            if token.nodeType == "," {
                groups.append([])
            } else {
                groups[groups.count - 1].append(token)
            }
        }
        if groups.last?.isEmpty == true { groups.removeLast() }
        return groups.map { predicate(from: $0, data: data) }
    }

    private static func predicate(from tokens: [Node], data: Data) -> RustCfgPredicate {
        guard let head = tokens.first, head.nodeType == "identifier" else { return .unparsed }
        let name = String(decoding: data[head.intByteRange], as: UTF8.self)
        switch tokens.count {
        case 1:
            return .flag(name)
        case 2 where tokens[1].nodeType == "token_tree":
            let items = list(in: tokens[1], data: data)
            switch name {
            case "all": return .all(items)
            case "any": return .any(items)
            case "not": return items.count == 1 ? .not(items[0]) : .unparsed
            default: return .unparsed
            }
        case 3 where tokens[1].nodeType == "=":
            return .keyValue(name)
        default:
            return .unparsed
        }
    }
}
