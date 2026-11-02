import Foundation
import Testing
@testable import Radiology

/// The frontier rules on synthetic graphs: critical emits, ordinary with a
/// body traverses transparently, unknown is listed and never traversed,
/// cycles/self-recursion/diamonds terminate without duplicate inflation, and
/// caps are explicit.
struct CriticalFrontierTests {
    static func id(_ name: String) -> SemanticSymbolID { SemanticSymbolID(symbol: "rust-analyzer cargo app 0.1.0 \(name)().", document: "") }
    static func position(_ name: String) -> SemanticPosition {
        SemanticPosition(path: "src/\(name).rs", range: SCIPRange(startLine: 0, startCharacter: 3, endLine: 0, endCharacter: 3 + name.count), encoding: .utf8)
    }

    static func call(_ name: String, _ criticality: Criticality, body: Bool = true, macro: Bool = false, sites: Int = 1) -> DirectCall {
        let reason: CriticalityClassification.Reason = switch criticality {
        case .critical: .repositoryDefinition
        case .ordinary: .runtimePlumbing
        case .unknown: .external
        }
        return DirectCall(callee: id(name), displayName: name, kind: SemanticSymbolKind(rawValue: 17),
                          classification: CriticalityClassification(criticality: criticality, reason: reason),
                          firstSiteByte: 0, siteCount: sites, definition: body ? position(name) : nil, isMacro: macro)
    }

    static func summary(_ name: String, _ calls: [DirectCall], coverage: CallCoverage = .complete) -> CallableSummary {
        CallableSummary(callable: id(name), body: CallableBody(path: "src/\(name).rs", byteRange: 0..<10, sourceIdentity: SourceContentIdentity(Data())),
                        calls: calls, conditional: [], coverage: coverage)
    }

    @Test func viaPathsDedupCyclesAndDiamonds() async {
        let root = Self.summary("root", [Self.call("a", .ordinary), Self.call("b", .critical), Self.call("c", .unknown), Self.call("m", .ordinary, body: false)])
        let bodies: [SemanticSymbolID: CallableSummary] = [
            Self.id("a"): Self.summary("a", [Self.call("d", .critical), Self.call("root", .ordinary), Self.call("a", .ordinary), Self.call("e", .ordinary)]),
            Self.id("e"): Self.summary("e", [Self.call("d", .critical), Self.call("f", .critical), Self.call("c", .unknown), Self.call("b", .critical)]),
        ]
        let frontier = await CriticalFrontierBuilder().build(root: root) { bodies[$0] }
        #expect(frontier.directCritical.map(\.displayName) == ["b"])
        #expect(frontier.paths.map(\.displayName) == ["d", "f"], "d once (first path), f via a › e; b is direct, never re-emitted")
        #expect(frontier.paths[0].viaDescription == "a")
        #expect(frontier.paths[1].viaDescription == "a › e")
        #expect(frontier.reachableCriticalCount == 3, "distinct union: b, d, f")
        #expect(frontier.unknown.map(\.displayName) == ["c"], "unknown listed once, never traversed or counted")
        #expect(frontier.coverage == .partial(CallCoverageGaps(unknownCallees: 1)), "an unknown callee may hide critical behavior: partial; an ordinary callee without a body is transparent")
        #expect(frontier.traversedBodies == 2, "a and e; root (cycle) and a (self) are not re-entered")
        #expect(frontier.statusLine == "1 direct · 3 reachable · partial")
        let withoutUnknown = Self.summary("root", [Self.call("a", .ordinary), Self.call("b", .critical), Self.call("m", .ordinary, body: false)])
        let clean = await CriticalFrontierBuilder().build(root: withoutUnknown) { bodies[$0] }
        #expect(clean.coverage == .partial(CallCoverageGaps(unknownCallees: 1)), "the unknown met inside e still counts")
    }

    @Test func unknownOrConditionalOnlyFunctionsAreNeverProvenZero() async {
        let onlyUnknown = Self.summary("u", [Self.call("mystery", .unknown, body: false)])
        let unknownFrontier = await CriticalFrontierBuilder().build(root: onlyUnknown) { _ in nil }
        #expect(unknownFrontier.annotation == CountAnnotation(count: 0, completeness: .partial))
        #expect(!unknownFrontier.annotation.isProvenZero)
        #expect(unknownFrontier.statusLine == "0 direct · partial")
        #expect(unknownFrontier.statusDetail.contains("Unknown callees"))

        let closureOnly = CallableSummary(callable: Self.id("c"), body: CallableBody(path: "src/c.rs", byteRange: 0..<10, sourceIdentity: SourceContentIdentity(Data())),
                                          calls: [], conditional: [ConditionalCallable(kind: .closure, name: nil, byteRange: 2..<8, siteCount: 2)],
                                          coverage: .complete)
        let closureFrontier = await CriticalFrontierBuilder().build(root: closureOnly) { _ in nil }
        #expect(closureFrontier.annotation == CountAnnotation(count: 0, completeness: .partial), "closure-owned calls are unproven, not a proven zero")
        #expect(closureFrontier.directCritical.isEmpty, "and never become outer direct edges")
        #expect(closureFrontier.statusLine == "0 direct · 2 conditional · partial")
        #expect(closureFrontier.statusDetail.contains("closures"))
        // Conditional sites inside a traversed ordinary body count as well.
        let root = Self.summary("r", [Self.call("c", .ordinary)])
        let through = await CriticalFrontierBuilder().build(root: root) { $0 == Self.id("c") ? closureOnly : nil }
        #expect(through.coverage.gaps?.conditionalSites == 2)
    }

    @Test func capsMissingBodiesMacrosAndNoBodyAreExplicit() async {
        let root = Self.summary("root", [Self.call("a", .ordinary), Self.call("mac", .ordinary, macro: true)],
                                coverage: .partial(CallCoverageGaps(unresolvedSites: 1, macroSites: 1)))
        let chain: [SemanticSymbolID: CallableSummary] = [
            Self.id("a"): Self.summary("a", [Self.call("b", .ordinary)]),
            Self.id("b"): Self.summary("b", [Self.call("c", .ordinary)]),
            Self.id("c"): Self.summary("c", [Self.call("z", .critical)]),
        ]
        let depthLimited = await CriticalFrontierBuilder(maxDepth: 2, maxBodies: 48).build(root: root) { chain[$0] }
        #expect(depthLimited.paths.isEmpty)
        #expect(depthLimited.isTruncated)
        #expect(depthLimited.coverage.gaps?.unresolvedSites == 1 && depthLimited.coverage.gaps?.macroSites == 1)
        #expect(depthLimited.statusLine == "0 direct · partial")
        let full = await CriticalFrontierBuilder(maxDepth: 6, maxBodies: 48).build(root: root) { chain[$0] }
        #expect(full.paths.map(\.viaDescription) == ["a › b › c"])
        #expect(!full.isTruncated)
        #expect(full.annotation == CountAnnotation(count: 1, completeness: .partial))
        let bodyLimited = await CriticalFrontierBuilder(maxDepth: 6, maxBodies: 1).build(root: root) { chain[$0] }
        #expect(bodyLimited.isTruncated && bodyLimited.paths.isEmpty)
        // A missing body for an ordinary callee that should have one is a gap.
        let missing = await CriticalFrontierBuilder().build(root: Self.summary("r", [Self.call("gone", .ordinary)])) { _ in nil }
        #expect(missing.coverage.gaps?.missingBodies == 1)
        #expect(missing.annotation.completeness == .partial)
        // A callee body reported as abstract counts as missing, not proven.
        let abstract = await CriticalFrontierBuilder().build(root: Self.summary("r", [Self.call("t", .ordinary)])) { _ in .noBody(.abstract, callable: Self.id("t")) }
        #expect(abstract.coverage.gaps?.missingBodies == 1)
        // Proven zero only with complete coverage and nothing reachable.
        let empty = await CriticalFrontierBuilder().build(root: Self.summary("r", [])) { _ in nil }
        #expect(empty.annotation == CountAnnotation(count: 0, completeness: .proven))
        #expect(empty.annotation.isProvenZero && empty.annotation.label == "0")
        #expect(empty.statusLine == "0 direct · proven")
        let noBody = await CriticalFrontierBuilder().build(root: .noBody(.external, callable: Self.id("x"))) { _ in nil }
        #expect(noBody.coverage == .noBody(.external))
        #expect(noBody.annotation.label == "\u{2013}")
        #expect(CountAnnotation(count: 3, completeness: .partial).label == "3+")
    }
}
