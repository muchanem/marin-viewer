import Foundation
import SwiftTreeSitter

/// Source structure only. An impl becomes a semantic result only after its
/// implemented trait's terminal name token resolves to an exact SCIP identity.
struct RustTraitImplSyntax: Sendable, Equatable {
    let byteRange: Range<Int>
    let traitNameRange: Range<Int>
    let signature: String
    let targetType: String
    let isNegative: Bool

    static func extract(root: Node, data: Data) throws -> [RustTraitImplSyntax] {
        var pending = [root]
        var results: [RustTraitImplSyntax] = []
        func text(_ range: Range<Int>) -> String {
            String(decoding: data[range], as: UTF8.self)
        }
        while let node = pending.popLast() {
            try Task.checkCancellation()
            if node.nodeType == "impl_item", let trait = node.child(byFieldName: "trait"),
               let name = terminalName(trait), let type = node.child(byFieldName: "type"),
               let body = node.child(byFieldName: "body"), !node.hasError {
                let header = node.intByteRange.lowerBound..<body.intByteRange.lowerBound
                let signature = text(header).trimmingCharacters(in: .whitespacesAndNewlines)
                results.append(RustTraitImplSyntax(byteRange: node.intByteRange,
                    traitNameRange: name.intByteRange, signature: signature, targetType: text(type.intByteRange),
                    isNegative: node.childNodes(namedOnly: false).contains { $0.nodeType == "!" }))
            }
            // Macro token trees are unexpanded source; they cannot prove impls.
            if node.nodeType != "token_tree" { pending.append(contentsOf: node.childNodes().reversed()) }
        }
        return results.sorted { $0.byteRange.lowerBound < $1.byteRange.lowerBound }
    }

    /// Peel generics before selecting the path's name. A trait in a type
    /// argument or bound must never be mistaken for the implemented trait.
    private static func terminalName(_ node: Node) -> Node? {
        switch node.nodeType {
        case "type_identifier", "identifier": node
        case "generic_type": node.child(byFieldName: "type").flatMap(terminalName)
        case "scoped_type_identifier", "scoped_identifier": node.child(byFieldName: "name").flatMap(terminalName)
        default: nil
        }
    }
}
