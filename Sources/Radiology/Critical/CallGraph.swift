import Foundation

/// How much of a callable's reachable operations a summary actually proves.
/// `complete` means every site resolved and every traversed body parsed, so
/// a count of zero is a proven zero. Anything else is said plainly.
enum CallCoverage: Sendable, Equatable {
    case complete
    case partial(CallCoverageGaps)
    case noBody(NoBodyReason)

    var isComplete: Bool { self == .complete }
    var gaps: CallCoverageGaps? { if case .partial(let gaps) = self { gaps } else { nil } }
}

struct CallCoverageGaps: Sendable, Equatable {
    /// Syntactic call sites with no SCIP occurrence at the callee name.
    var unresolvedSites = 0
    /// Macro invocations: their expansion is unknown.
    var macroSites = 0
    /// Ordinary callees with an in-repository definition whose body could
    /// not be read, parsed, or found.
    var missingBodies = 0
    /// Depth or node limits stopped the traversal.
    var truncated = false
    /// A traversed file did not fully parse, so its sites may be incomplete.
    var parseErrors = false
    /// Distinct callees with no classification: they may hide critical
    /// behavior, so a count that met one is a lower bound.
    var unknownCallees = 0
    /// Call sites inside closures and nested functions: whether they run is
    /// unproven, so they are neither counted nor allowed to prove zero.
    var conditionalSites = 0

    var isEmpty: Bool {
        unresolvedSites == 0 && macroSites == 0 && missingBodies == 0 && !truncated && !parseErrors
            && unknownCallees == 0 && conditionalSites == 0
    }

    mutating func merge(_ other: CallCoverageGaps) {
        unresolvedSites += other.unresolvedSites
        macroSites += other.macroSites
        missingBodies += other.missingBodies
        truncated = truncated || other.truncated
        parseErrors = parseErrors || other.parseErrors
        unknownCallees += other.unknownCallees
        conditionalSites += other.conditionalSites
    }

    /// Short, honest phrasing for a status line.
    var description: String {
        var parts: [String] = []
        if unresolvedSites > 0 { parts.append("\(unresolvedSites) unresolved") }
        if macroSites > 0 { parts.append(macroSites == 1 ? "1 macro" : "\(macroSites) macros") }
        if missingBodies > 0 { parts.append(missingBodies == 1 ? "1 body missing" : "\(missingBodies) bodies missing") }
        if truncated { parts.append("truncated") }
        if parseErrors { parts.append("parse errors") }
        if unknownCallees > 0 { parts.append("\(unknownCallees) unknown") }
        if conditionalSites > 0 { parts.append("\(conditionalSites) conditional") }
        return parts.joined(separator: " · ")
    }
}

enum NoBodyReason: String, Sendable {
    case external
    case abstract
    case noSyntax
    case unreadable
    case notIndexed
    case unsupportedLanguage

    var description: String {
        switch self {
        case .external: "defined outside this repository"
        case .abstract: "declaration without a body"
        case .noSyntax: "no parsed structure"
        case .unreadable: "file could not be read"
        case .notIndexed: "file not in the index"
        case .unsupportedLanguage: "no call-site support for this language"
        }
    }
}

/// One resolved direct call of a callable: a syntactic site whose callee
/// name is a SCIP occurrence. Several sites of one callee collapse into one
/// entry that keeps the first site.
struct DirectCall: Sendable, Equatable, Identifiable {
    let callee: SemanticSymbolID
    let displayName: String
    let kind: SemanticSymbolKind
    let classification: CriticalityClassification
    /// Canonical byte of the first site's name in the owner's file.
    let firstSiteByte: Int
    let siteCount: Int
    /// The first in-repository definition, or nil when there is none.
    let definition: SemanticPosition?
    let isMacro: Bool
    var id: String { callee.description }
    var hasBody: Bool { definition != nil }
}

/// Where a summary's sites came from: the exact bytes of one callable body.
struct CallableBody: Sendable, Equatable {
    let path: String
    let byteRange: Range<Int>
    let sourceIdentity: SourceContentIdentity
}

/// Direct calls of one callable, with lexical ownership honored: sites inside
/// closures and nested named functions are not here; they are reported as
/// conditional nodes.
struct CallableSummary: Sendable, Equatable {
    let callable: SemanticSymbolID?
    let body: CallableBody?
    /// Source order of first site, one entry per callee.
    let calls: [DirectCall]
    let conditional: [ConditionalCallable]
    let coverage: CallCoverage

    var criticalCalls: [DirectCall] { calls.filter { $0.classification.criticality == .critical } }
    var unknownCalls: [DirectCall] { calls.filter { $0.classification.criticality == .unknown } }
    var conditionalSiteCount: Int { conditional.reduce(0) { $0 + $1.siteCount } }

    static func noBody(_ reason: NoBodyReason, callable: SemanticSymbolID?) -> CallableSummary {
        CallableSummary(callable: callable, body: nil, calls: [], conditional: [], coverage: .noBody(reason))
    }
}

/// An ordinary intermediary on the way to a critical callee.
struct ViaStep: Sendable, Equatable {
    let symbol: SemanticSymbolID
    let displayName: String
    let definition: SemanticPosition?
}

/// A critical (or unknown) callee reachable from the root, with the ordinary
/// callables it was reached through. `via` is empty for a direct call.
struct CriticalPath: Sendable, Equatable, Identifiable {
    let callee: SemanticSymbolID
    let displayName: String
    let kind: SemanticSymbolKind
    let classification: CriticalityClassification
    let definition: SemanticPosition?
    let via: [ViaStep]
    let depth: Int
    var id: String { callee.description }
    var isDirect: Bool { via.isEmpty }
    var viaDescription: String { via.map(\.displayName).joined(separator: " › ") }
}

/// The bounded reachable set of critical operations from one callable.
struct CriticalFrontier: Sendable, Equatable {
    let summary: CallableSummary
    /// Critical callees reached through ordinary intermediaries, in
    /// breadth-first source order, one entry per callee (shortest path).
    let paths: [CriticalPath]
    /// Unknown callees met at any depth; never traversed, never counted.
    let unknown: [CriticalPath]
    let coverage: CallCoverage
    let traversedBodies: Int

    var directCritical: [DirectCall] { summary.criticalCalls }
    /// Distinct union of direct critical callees and frontier callees.
    var reachableCriticalCount: Int {
        Set(directCritical.map(\.callee)).union(paths.map(\.callee)).count
    }
    var isTruncated: Bool { coverage.gaps?.truncated == true }

    /// Generic count presentation for gutters and outlines.
    var annotation: CountAnnotation {
        switch coverage {
        case .noBody: CountAnnotation(count: 0, completeness: .noBody)
        case .partial: CountAnnotation(count: reachableCriticalCount, completeness: .partial)
        case .complete: CountAnnotation(count: reachableCriticalCount, completeness: .proven)
        }
    }

    /// One short line: "3 direct · 7 reachable · partial".
    var statusLine: String {
        if case .noBody(let reason) = coverage { return "No body · \(reason.description)" }
        var parts = ["\(directCritical.count) direct"]
        if reachableCriticalCount != directCritical.count { parts.append("\(reachableCriticalCount) reachable") }
        if !summary.conditional.isEmpty {
            let sites = summary.conditionalSiteCount
            parts.append("\(sites) conditional")
        }
        parts.append(coverage.isComplete ? (reachableCriticalCount == 0 ? "proven" : "complete") : "partial")
        return parts.joined(separator: " · ")
    }

    var statusDetail: String {
        switch coverage {
        case .noBody(let reason):
            return "There is no body to summarize: \(reason.description)."
        case .complete:
            return reachableCriticalCount == 0
                ? "Every call site resolved and every traversed body was parsed: no critical operation is reachable."
                : "Every call site resolved and every traversed body was parsed."
        case .partial(let gaps):
            var text = "Coverage is partial (\(gaps.description)), so the count is a lower bound."
            if gaps.unknownCallees > 0 {
                text += " Unknown callees are not classified and may hide critical behavior."
            }
            if gaps.conditionalSites > 0 {
                text += " Call sites inside closures or nested functions run conditionally and are not counted as direct calls."
            }
            return text
        }
    }
}

/// A count a reader or gutter can draw without knowing what was counted.
/// Proven zero recedes; partial and no-body are visibly distinct from it.
struct CountAnnotation: Sendable, Equatable, Hashable {
    enum Completeness: Sendable { case proven, partial, noBody }
    let count: Int
    let completeness: Completeness

    var isProvenZero: Bool { completeness == .proven && count == 0 }

    /// `3`, `3+` (at least), or `–` (nothing to count).
    var label: String {
        switch completeness {
        case .proven: "\(count)"
        case .partial: "\(count)+"
        case .noBody: "\u{2013}"
        }
    }

    var accessibilityDescription: String {
        switch completeness {
        case .proven: count == 0 ? "no critical operations reachable, proven" : "\(count) critical operations reachable"
        case .partial: "at least \(count) critical operations reachable, coverage partial"
        case .noBody: "no body to summarize"
        }
    }
}

extension SemanticSymbolID {
    /// A method or function by SCIP descriptor (`().`), or by indexed kind.
    /// External symbols have no kind, so the descriptor is what decides.
    func isCallable(in index: SemanticIndex) -> Bool {
        if symbol.hasSuffix("().") { return true }
        guard let kind = index.symbols[self]?.kind else { return false }
        return kind.category == .function
    }
}
