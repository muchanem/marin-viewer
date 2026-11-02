import Foundation
import Testing
@testable import Radiology

/// Syntactic call sites per grammar: named shapes get a callee token, every
/// other call shape is kept as an unresolved `dynamic` site, and ownership
/// follows the innermost function or closure.
struct CallSiteExtractionTests {
    static func site(_ snapshot: SyntaxSnapshot, named name: String, in buffer: SourceBuffer) -> CallSite? {
        snapshot.callSites.first { $0.nameByteRange.map { buffer.text(in: $0) } == name }
    }

    @Test(arguments: SyntaxFixtures.names)
    func everyFixtureReportsNamedCallSites(_ fixture: String) async throws {
        let (buffer, snapshot) = try await SyntaxFixtures.snapshot(fixture)
        #expect(snapshot.supportsCallSites, "\(fixture) has no calls query")
        let named = snapshot.callSites.filter { $0.nameByteRange != nil }
        #expect(!named.isEmpty, "\(fixture) yields no named call sites")
        for site in snapshot.callSites {
            if let name = site.nameByteRange {
                #expect(site.byteRange.lowerBound <= name.lowerBound && name.upperBound <= site.byteRange.upperBound)
                #expect(!buffer.text(in: name).isEmpty)
            }
        }
        // Sorted by position and unique by site.
        #expect(snapshot.callSites.map(\.anchorByte) == snapshot.callSites.map(\.anchorByte).sorted())
        #expect(Set(snapshot.callSites.map(\.byteRange)).count == snapshot.callSites.count)
    }

    @Test func rustShapesMacrosAndOwnership() async throws {
        let (buffer, snapshot) = try await SyntaxFixtures.snapshot("sample.rs")
        let format = try #require(Self.site(snapshot, named: "format", in: buffer))
        #expect(format.isMacro)
        #expect(try #require(Self.site(snapshot, named: "println", in: buffer)).isMacro)
        #expect(try #require(Self.site(snapshot, named: "to_string", in: buffer)).kind == "call")
        #expect(Self.site(snapshot, named: "render", in: buffer) != nil, "method call")
        #expect(Self.site(snapshot, named: "default", in: buffer) != nil, "scoped call Default::default")
        // `closure(MAX_SCANS as i32)` sits inside `println!`'s token tree: not a
        // call node, so not a site. The macro itself is the (unknown) site.
        #expect(Self.site(snapshot, named: "closure", in: buffer) == nil)
        #expect(snapshot.callSites.allSatisfy { $0.nameByteRange != nil }, "every shape in the fixture is named")

        // Ownership: the impl's `render` body owns format/println; the trait requirement has no body.
        let renders = snapshot.symbols.filter { $0.name == "render" && $0.kind == "function" }
        let render = try #require(renders.max { $0.byteRange.count < $1.byteRange.count })
        let renderRequirement = try #require(renders.min { $0.byteRange.count < $1.byteRange.count })
        let renderSites = snapshot.directCallSites(within: render.byteRange).map { buffer.text(in: $0.nameByteRange!) }
        #expect(renderSites == ["format", "println"])
        let main = try #require(snapshot.symbols.first { $0.name == "main" })
        let mainSites = snapshot.directCallSites(within: main.byteRange).map { buffer.text(in: $0.nameByteRange!) }
        #expect(mainSites == ["to_string", "default", "render", "println"])
        let conditional = snapshot.conditionalCallables(within: main.byteRange)
        #expect(conditional.count == 1 && conditional[0].kind == .closure && conditional[0].siteCount == 0)
        #expect(snapshot.hasBody(render))
        #expect(!snapshot.hasBody(renderRequirement), "the trait requirement has no body")
    }

    @Test func dynamicCalleesClosuresAndNestedFunctionsStayHonest() async throws {
        let source = """
        fn outer(f: fn(i32) -> i32, g: &dyn Fn()) {
            (f)(1);
            (g)();
            let adder = |x: i32| helper(x);
            fn inner() { helper(2); }
            adder(3);
            inner();
            // helper(99) in a comment and "helper(100)" in a string are not sites
            let s = "helper(100)";
        }
        fn helper(x: i32) -> i32 { x }
        """
        let buffer = try SourceBuffer(path: "dyn.rs", data: Data(source.utf8))
        let snapshot = try #require(try await SyntaxWorker().parse(buffer))
        let dynamic = snapshot.callSites.filter { $0.kind == "dynamic" }
        #expect(dynamic.count == 2, "parenthesized callees are kept as unresolved sites: \(snapshot.callSites)")
        #expect(dynamic.allSatisfy { $0.nameByteRange == nil })
        let outer = try #require(snapshot.symbols.first { $0.name == "outer" })
        let direct = snapshot.directCallSites(within: outer.byteRange)
        let names = direct.map { $0.nameByteRange.map { buffer.text(in: $0) } ?? "<dynamic>" }
        #expect(names == ["<dynamic>", "<dynamic>", "adder", "inner"], "closure and nested-fn sites are not outer's: \(names)")
        let conditional = snapshot.conditionalCallables(within: outer.byteRange)
        #expect(conditional.map(\.kind) == [.closure, .function])
        #expect(conditional.map(\.siteCount) == [1, 1])
        #expect(conditional[1].name == "inner")
        #expect(snapshot.callSites.count { $0.nameByteRange.map { buffer.text(in: $0) } == "helper" } == 2, "only the two real calls, not the comment or string")
    }

    @Test func otherGrammarsNameMethodAndFunctionCalls() async throws {
        let (go, goSnapshot) = try await SyntaxFixtures.snapshot("sample.go")
        #expect(Self.site(goSnapshot, named: "Sprintf", in: go) != nil)
        #expect(Self.site(goSnapshot, named: "append", in: go) != nil)
        let (swift, swiftSnapshot) = try await SyntaxFixtures.snapshot("sample.swift")
        #expect(Self.site(swiftSnapshot, named: "append", in: swift) != nil)
        #expect(Self.site(swiftSnapshot, named: "joined", in: swift) != nil)
        let (python, pythonSnapshot) = try await SyntaxFixtures.snapshot("sample.py")
        #expect(Self.site(pythonSnapshot, named: "open", in: python) != nil)
        #expect(Self.site(pythonSnapshot, named: "read", in: python) != nil)
        let (kotlin, kotlinSnapshot) = try await SyntaxFixtures.snapshot("sample.kt")
        #expect(Self.site(kotlinSnapshot, named: "max", in: kotlin) != nil)
        #expect(Self.site(kotlinSnapshot, named: "mutableListOf", in: kotlin) != nil)
        let (ts, tsSnapshot) = try await SyntaxFixtures.snapshot("sample.ts")
        #expect(!tsSnapshot.callSites.isEmpty)
    }
}
