import Foundation
import Testing
@testable import Radiology

struct CSyntaxTests {
    @Test func cProvidesStructureAndRecursiveDeclaratorNames() async throws {
        let (buffer, syntax) = try await SyntaxFixtures.snapshot("sample.c")
        #expect(!syntax.hasParseErrors)
        #expect(syntax.highlight(named: "type.builtin", text: "int", in: buffer))
        #expect(syntax.highlight(named: "function", text: "measure", in: buffer))
        #expect(syntax.symbol("type", "Scan"))
        #expect(syntax.symbol("enum", "Modality"))
        #expect(syntax.symbol("typealias", "ScanID"))
        #expect(syntax.symbol("macro", "TWICE"))
        #expect(syntax.symbol("function", "titles"), "pointer return declarators must reach their name")
        #expect(syntax.symbol("function", "render"))
        let names = syntax.callSites.compactMap { $0.nameByteRange.map { buffer.text(in: $0) } }
        #expect(names.contains("measure"))
        #expect(names.contains("callback"))
        #expect(!names.contains("fake_call"))
        let titles = try #require(syntax.symbols.first { $0.name == "titles" })
        #expect(buffer.text(in: titles.selectionByteRange) == "titles")
        #expect(syntax.enclosingFunctionFold(at: titles.selectionByteRange.lowerBound)?.function == titles)
    }

    @Test func cppRetainsMethodsTemplatesQualifiedCallsAndLambdaOwnership() async throws {
        let (buffer, syntax) = try await SyntaxFixtures.snapshot("sample.cpp")
        #expect(!syntax.hasParseErrors)
        #expect(syntax.symbol("module", "imaging"))
        #expect(syntax.symbol("type", "Scan"))
        #expect(syntax.symbol("method", "render"))
        #expect(syntax.symbol("method", "~Scan"))
        #expect(syntax.symbol("method", "operator+="))
        #expect(syntax.symbol("typealias", "ScanID"))
        #expect(syntax.symbol("function", "titles"))
        #expect(syntax.highlight(named: "keyword", text: "template", in: buffer))
        let render = try #require(syntax.symbols.first { $0.name == "render" })
        #expect(syntax.enclosingFunctionFold(at: render.selectionByteRange.lowerBound)?.function == render)
        #expect(syntax.scopes.contains { $0.kind == "closure" })
        #expect(!syntax.directCallSites(within: render.byteRange).contains { $0.nameByteRange.map { buffer.text(in: $0) } == "twice" })
        #expect(syntax.conditionalCallables(within: render.byteRange).first?.siteCount == 1)
        let load = try #require(syntax.symbols.first { $0.name == "load" })
        let sites = syntax.directCallSites(within: load.byteRange)
        let names = sites.compactMap { $0.nameByteRange.map { buffer.text(in: $0) } }
        #expect(names.contains("render"))
        #expect(names.contains("twice"))
    }

    @Test func plainHeadersParseBothCAndCppWithoutFunctionPointerOutlines() async throws {
        let data = Data("typedef int (*Callback)(int);\nint (*handler)(int);\nstruct Scan { int value; };\nclass Reader { public: int read(); };\n".utf8)
        let syntax = try #require(try await SyntaxWorker().parse(SourceBuffer(path: "reader.h", data: data)))
        #expect(syntax.languageID == "cpp")
        #expect(!syntax.hasParseErrors)
        #expect(syntax.symbol("typealias", "Callback"))
        #expect(!syntax.symbol("function", "handler"))
        #expect(syntax.symbol("method", "read"))
    }

    @Test func newAndDeleteRetainUnknownConstructionAndDestructionSites() async throws {
        let data = Data("struct Thing {};\nThing *make() { return new Thing(); }\nvoid drop(Thing *value) { delete value; }\n".utf8)
        let buffer = try SourceBuffer(path: "allocation.cpp", data: data)
        let syntax = try #require(try await SyntaxWorker().parse(buffer))
        #expect(!syntax.hasParseErrors)
        #expect(syntax.callSites.count == 2)
        #expect(syntax.callSites.allSatisfy { $0.kind == "dynamic" && $0.nameByteRange == nil })
    }
}
