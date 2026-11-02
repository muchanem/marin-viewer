import SwiftTreeSitter

/// C/C++ names sit on a recursive declarator spine. Following fields avoids
/// accidentally choosing a parameter, return type, or initializer identifier.
enum CDeclarationSyntax {
    static func name(in capture: Node, requireFunction: Bool = false, allowFunctionPointer: Bool = false) -> Node? {
        var node = capture
        var foundFunction = false
        while true {
            switch node.nodeType {
            case "identifier", "field_identifier", "type_identifier", "namespace_identifier",
                 "nested_namespace_specifier", "destructor_name", "operator_name":
                return requireFunction && !foundFunction ? nil : node
            case "function_declarator":
                foundFunction = true
                guard let child = node.child(byFieldName: "declarator"),
                      allowFunctionPointer || child.nodeType != "parenthesized_declarator" else { return nil }
                node = child
            case "qualified_identifier", "template_function", "template_method", "template_type":
                guard let child = node.child(byFieldName: "name") else { return nil }
                node = child
            case "reference_declarator", "parenthesized_declarator":
                guard let child = node.childNodes().last else { return nil }
                node = child
            default:
                guard let child = node.child(byFieldName: "declarator") else { return nil }
                node = child
            }
        }
    }
}
