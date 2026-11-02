import Foundation
import SwiftTreeSitter

/// JavaScript, TypeScript, and TSX: program-level test-framework calls and
/// Vitest in-source blocks. A framework name counts only when the file does
/// not bind it itself, or binds it from a known test module.
extension TestRegionDetector {
    static let ecmascriptTestCallees: Set<String> = [
        "describe", "it", "test", "suite", "context", "xit", "xdescribe", "fit", "fdescribe",
        "beforeEach", "afterEach", "beforeAll", "afterAll",
    ]
    static let ecmascriptTestModules: Set<String> = [
        "vitest", "bun:test", "@jest/globals", "node:test", "mocha", "@playwright/test", "jest", "uvu", "ava",
    ]
    static let ecmascriptFunctionNodes: Set<String> = [
        "arrow_function", "function_expression", "function", "generator_function",
    ]

    func ecmascriptRegions(in program: Node, into regions: inout [TestRegion]) {
        let children = program.childNodes()
        var bindings = Bindings()
        for child in children { collectBindings(child, into: &bindings) }
        for (index, child) in children.enumerated() {
            if child.nodeType == "if_statement", isVitestInSourceGuard(child) {
                regions.append(region(siblings: children, from: index, through: index, evidence: .inSourceTests))
            } else if child.nodeType == "expression_statement",
                      let call = child.childNodes().first, call.nodeType == "call_expression",
                      isTestCall(call, bindings: bindings) {
                regions.append(region(siblings: children, from: index, through: index, evidence: .testCall))
            }
        }
    }

    private struct Bindings {
        /// Names bound in this file by anything other than a test-module import.
        var local: Set<String> = []
        /// Names imported (or required) from a known test module.
        var fromTestModule: Set<String> = []
    }

    private func isTestCall(_ call: Node, bindings: Bindings) -> Bool {
        guard let arguments = call.child(byFieldName: "arguments"),
              arguments.childNodes().contains(where: { Self.ecmascriptFunctionNodes.contains($0.nodeType ?? "") }),
              let path = calleePath(call), let root = path.first else { return false }
        if root == "Deno" { return path.count >= 2 && path[1] == "test" && !bindings.local.contains("Deno") }
        guard Self.ecmascriptTestCallees.contains(root) else { return false }
        return bindings.fromTestModule.contains(root) || !bindings.local.contains(root)
    }

    /// `describe.each(table)("name", fn)` → ["describe", "each"]: the root
    /// identifier followed by member names, through nested calls.
    private func calleePath(_ call: Node) -> [String]? {
        var node = call.child(byFieldName: "function")
        var path: [String] = []
        while let current = node {
            switch current.nodeType {
            case "identifier":
                return [text(current)] + path.reversed()
            case "member_expression":
                if let property = current.child(byFieldName: "property") { path.append(text(property)) }
                node = current.child(byFieldName: "object")
            case "call_expression":
                node = current.child(byFieldName: "function")
            default:
                return nil
            }
        }
        return nil
    }

    private func isVitestInSourceGuard(_ statement: Node) -> Bool {
        guard statement.child(byFieldName: "alternative") == nil,
              let condition = statement.child(byFieldName: "condition") else { return false }
        return text(condition).filter { !$0.isWhitespace } == "(import.meta.vitest)"
    }

    private func collectBindings(_ node: Node, into bindings: inout Bindings) {
        switch node.nodeType {
        case "import_statement":
            let source = node.child(byFieldName: "source").map(text)?.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
            let isTestModule = source.map(Self.ecmascriptTestModules.contains) ?? false
            for name in importedNames(node) {
                if isTestModule { bindings.fromTestModule.insert(name) } else { bindings.local.insert(name) }
            }
        case "lexical_declaration", "variable_declaration":
            for declarator in node.childNodes() where declarator.nodeType == "variable_declarator" {
                let names = declarator.child(byFieldName: "name").map(patternNames) ?? []
                if let value = declarator.child(byFieldName: "value"), isTestModuleRequire(value) {
                    bindings.fromTestModule.formUnion(names)
                } else {
                    bindings.local.formUnion(names)
                }
            }
        case "function_declaration", "generator_function_declaration", "class_declaration":
            if let name = node.child(byFieldName: "name") { bindings.local.insert(text(name)) }
        case "export_statement":
            for child in node.childNodes() { collectBindings(child, into: &bindings) }
        default:
            break
        }
    }

    private func importedNames(_ statement: Node) -> [String] {
        guard let clause = statement.childNodes().first(where: { $0.nodeType == "import_clause" }) else { return [] }
        var names: [String] = []
        for part in clause.childNodes() {
            switch part.nodeType {
            case "identifier":
                names.append(text(part))
            case "namespace_import":
                names += part.childNodes().filter { $0.nodeType == "identifier" }.map(text)
            case "named_imports":
                for specifier in part.childNodes() where specifier.nodeType == "import_specifier" {
                    if let bound = specifier.child(byFieldName: "alias") ?? specifier.child(byFieldName: "name") {
                        names.append(text(bound))
                    }
                }
            default:
                break
            }
        }
        return names
    }

    private func patternNames(_ pattern: Node) -> [String] {
        switch pattern.nodeType {
        case "identifier", "shorthand_property_identifier_pattern":
            return [text(pattern)]
        default:
            return pattern.childNodes().flatMap(patternNames)
        }
    }

    /// `require("node:test")` (or another test module).
    private func isTestModuleRequire(_ value: Node) -> Bool {
        guard value.nodeType == "call_expression",
              value.child(byFieldName: "function").map(text) == "require",
              let argument = value.child(byFieldName: "arguments")?.childNodes().first,
              argument.nodeType == "string" else { return false }
        return Self.ecmascriptTestModules.contains(text(argument).trimmingCharacters(in: CharacterSet(charactersIn: "\"'`")))
    }
}
