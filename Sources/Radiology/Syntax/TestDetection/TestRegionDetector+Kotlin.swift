import Foundation
import SwiftTreeSitter

/// Kotlin: annotations live in a declaration's `modifiers`; the annotation's
/// `user_type` (possibly qualified, possibly a constructor invocation) names it.
extension TestRegionDetector {
    static let kotlinTestFunctionAnnotations: Set<String> = [
        "Test", "ParameterizedTest", "RepeatedTest", "TestFactory", "TestTemplate",
        "BeforeTest", "AfterTest", "BeforeEach", "AfterEach", "BeforeAll", "AfterAll",
    ]
    static let kotlinTestClassAnnotations: Set<String> = ["RunWith", "ExtendWith", "TestInstance"]
    static let kotestSpecs: Set<String> = [
        "StringSpec", "FunSpec", "DescribeSpec", "BehaviorSpec", "ShouldSpec", "WordSpec",
        "FreeSpec", "FeatureSpec", "ExpectSpec", "AnnotationSpec",
    ]

    /// Depth-first over an explicit stack, like the Rust walk.
    func kotlinRegions(in root: Node, into regions: inout [TestRegion]) {
        var pending = [root]
        while let node = pending.popLast() {
            let children = node.childNodes()
            for (index, child) in children.enumerated() {
                switch child.nodeType {
                case "class_declaration", "object_declaration":
                    if kotlinIsTestClass(child) {
                        regions.append(region(siblings: children, from: index, through: index, evidence: .testClass))
                        continue
                    }
                case "function_declaration":
                    if !kotlinAnnotationNames(of: child).isDisjoint(with: Self.kotlinTestFunctionAnnotations) {
                        regions.append(region(siblings: children, from: index, through: index, evidence: .testAnnotation))
                        continue
                    }
                case "string_literal", "multiline_comment", "line_comment":
                    continue
                default:
                    break
                }
                pending.append(child)
            }
        }
    }

    private func kotlinIsTestClass(_ declaration: Node) -> Bool {
        if !kotlinAnnotationNames(of: declaration).isDisjoint(with: Self.kotlinTestClassAnnotations) { return true }
        let children = declaration.childNodes()
        let supertypes = children.filter { $0.nodeType == "delegation_specifier" }
            .compactMap { $0.firstDescendant(ofType: "user_type") }
            .compactMap(kotlinTypeName)
        if supertypes.contains(where: Self.kotestSpecs.contains) { return true }
        guard let body = children.first(where: { $0.nodeType == "class_body" }) else { return false }
        return body.childNodes().contains { member in
            member.nodeType == "function_declaration"
                && !kotlinAnnotationNames(of: member).isDisjoint(with: Self.kotlinTestFunctionAnnotations)
        }
    }

    /// Simple names of a declaration's annotations (`org.junit.Test` → `Test`).
    private func kotlinAnnotationNames(of declaration: Node) -> Set<String> {
        guard let modifiers = declaration.childNodes().first(where: { $0.nodeType == "modifiers" }) else { return [] }
        return Set(modifiers.childNodes().filter { $0.nodeType == "annotation" }
            .compactMap { $0.firstDescendant(ofType: "user_type") }
            .compactMap(kotlinTypeName))
    }

    private func kotlinTypeName(_ userType: Node) -> String? {
        userType.childNodes().last { $0.nodeType == "type_identifier" }.map(text)
    }
}
