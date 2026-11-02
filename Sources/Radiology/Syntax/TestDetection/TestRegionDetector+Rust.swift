import Foundation
import SwiftTreeSitter

/// Rust: outer `attribute_item`s are siblings that precede the item they
/// annotate, in `source_file`, `declaration_list` (mod/impl/trait bodies),
/// blocks, field lists, and match arms alike.
extension TestRegionDetector {
    static let rustTestAttributeRoots: Set<String> = ["rstest", "test_case", "wasm_bindgen_test", "quickcheck"]

    /// Depth-first over an explicit stack: generated code can nest far
    /// deeper than a cooperative thread's stack allows recursion.
    func rustRegions(in root: Node, into regions: inout [TestRegion]) {
        var pending = [root]
        while let node = pending.popLast() {
            let children = node.childNodes()
            for (index, child) in children.enumerated() {
                guard let type = child.nodeType, !isRustAttributeOrComment(type) else { continue }
                // Macro bodies are unparsed token trees; strings hold no items.
                if type == "token_tree" || type == "string_literal" || type == "raw_string_literal" { continue }
                var first = index
                var attributes: [Node] = []
                var cursor = index - 1
                while cursor >= 0, let previous = children[cursor].nodeType, isRustAttributeOrComment(previous),
                      previous != "inner_attribute_item" {
                    if previous == "attribute_item" {
                        attributes.append(children[cursor])
                        first = cursor
                    }
                    cursor -= 1
                }
                if let evidence = rustTestEvidence(attributes: attributes, item: child) {
                    regions.append(region(siblings: children, from: first, through: index, evidence: evidence))
                } else {
                    pending.append(child)
                }
            }
        }
    }

    private func isRustAttributeOrComment(_ type: String) -> Bool {
        type == "attribute_item" || type == "inner_attribute_item" || type == "line_comment" || type == "block_comment"
    }

    private func rustTestEvidence(attributes: [Node], item: Node) -> TestRegion.Evidence? {
        for attribute in attributes.compactMap({ $0.childNodes().first { $0.nodeType == "attribute" } }) {
            if rustAttributeIsTestOnlyCfg(attribute) { return .cfgTest }
            if rustAttributeIsTest(attribute) { return .testAttribute }
        }
        if item.nodeType == "mod_item", let body = item.child(byFieldName: "body"),
           rustBodyIsTestOnly(body.childNodes()) {
            return .cfgTest
        }
        return nil
    }

    /// Leading inner attributes (`#![cfg(test)]`) of a file or module body.
    func rustBodyIsTestOnly(_ children: [Node]) -> Bool {
        for child in children {
            switch child.nodeType {
            case "inner_attribute_item":
                if let attribute = child.childNodes().first(where: { $0.nodeType == "attribute" }),
                   rustAttributeIsTestOnlyCfg(attribute) { return true }
            case "line_comment", "block_comment":
                continue
            default:
                return false
            }
        }
        return false
    }

    private func rustAttributePath(_ attribute: Node) -> String? {
        guard let path = attribute.childNodes().first,
              path.nodeType == "identifier" || path.nodeType == "scoped_identifier" else { return nil }
        return text(path).filter { !$0.isWhitespace }
    }

    private func rustAttributeIsTestOnlyCfg(_ attribute: Node) -> Bool {
        guard rustAttributePath(attribute) == "cfg",
              let arguments = attribute.child(byFieldName: "arguments"),
              arguments.nodeType == "token_tree" else { return false }
        return RustCfgPredicate.parse(arguments: arguments, data: data).isTestOnly
    }

    private func rustAttributeIsTest(_ attribute: Node) -> Bool {
        guard let path = rustAttributePath(attribute) else { return false }
        let segments = path.components(separatedBy: "::")
        return segments.last == "test" || segments.first.map(Self.rustTestAttributeRoots.contains) == true
    }
}
