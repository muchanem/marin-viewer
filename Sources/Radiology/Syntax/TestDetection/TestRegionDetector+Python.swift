import Foundation
import SwiftTreeSitter

/// Python, best effort and module level only. `unittest`-style classes are
/// recognized by their base class anywhere; pytest's naming conventions
/// count only in a module that imports pytest, because `def test_connection()`
/// is a perfectly good production function name.
extension TestRegionDetector {
    func pythonRegions(in module: Node, into regions: inout [TestRegion]) {
        let children = module.childNodes()
        let importsPytest = children.contains(where: pythonImportsPytest)
        for (index, child) in children.enumerated() {
            if let evidence = pythonTestEvidence(child, importsPytest: importsPytest) {
                regions.append(region(siblings: children, from: index, through: index, evidence: evidence))
            }
        }
    }

    private func pythonTestEvidence(_ node: Node, importsPytest: Bool) -> TestRegion.Evidence? {
        var definition = node
        if node.nodeType == "decorated_definition" {
            if importsPytest, node.childNodes().contains(where: { decorator in
                decorator.nodeType == "decorator"
                    && (text(decorator).hasPrefix("@pytest.fixture") || text(decorator).hasPrefix("@pytest.mark."))
            }) { return .pytest }
            guard let inner = node.child(byFieldName: "definition") else { return nil }
            definition = inner
        }
        let name = definition.child(byFieldName: "name").map(text) ?? ""
        switch definition.nodeType {
        case "class_definition":
            let bases = definition.child(byFieldName: "superclasses")?.childNodes() ?? []
            if bases.contains(where: { base in
                (base.nodeType == "identifier" || base.nodeType == "attribute")
                    && (text(base).split(separator: ".").last.map { $0.hasSuffix("TestCase") } ?? false)
            }) { return .testClass }
            return importsPytest && name.hasPrefix("Test") ? .pytest : nil
        case "function_definition":
            return importsPytest && name.hasPrefix("test_") ? .pytest : nil
        default:
            return nil
        }
    }

    private func pythonImportsPytest(_ node: Node) -> Bool {
        switch node.nodeType {
        case "import_statement":
            return node.childNodes().contains { name in
                let target = name.nodeType == "aliased_import" ? name.child(byFieldName: "name") : name
                return target.map(text)?.split(separator: ".").first == "pytest"
            }
        case "import_from_statement":
            return node.child(byFieldName: "module_name").map(text)?.split(separator: ".").first == "pytest"
        default:
            return false
        }
    }
}
