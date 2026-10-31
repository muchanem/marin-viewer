import Foundation

/// Structure extracted from one source file. All positions are canonical UTF-8
/// byte offsets into `SourceBuffer.data`; UTF-16 conversion happens only at the
/// TextKit boundary, through `SourceBuffer`.
struct SyntaxSnapshot: Equatable, Sendable {
    let path: String
    /// `SourceLanguage.id` of the grammar that produced this snapshot.
    let languageID: String
    let languageName: String
    /// Ordered for painting: outer ranges first, so narrower captures win.
    let highlights: [SyntaxHighlight]
    let folds: [SourceFold]
    let symbols: [DocumentSymbol]
    let scopes: [SourceScope]
    let hasParseErrors: Bool
    /// Call sites in source order; empty when the grammar ships no `calls`
    /// query. Each names a callee token to be resolved against SCIP.
    var callSites: [CallSite] = []
    /// Whether the grammar can report call sites at all, so an empty list
    /// means "none" rather than "unsupported".
    var supportsCallSites = false
    /// Test-only regions (sorted, disjoint, outermost); empty for grammars
    /// without test detection. See plans/source-filters.md.
    var testRegions: [TestRegion] = []
    /// The whole file compiles only for tests (Rust `#![cfg(test)]`).
    var isTestOnlyDocument = false
    var foldHeaderOwnership: [FoldHeaderOwnership] = []
    var rustTraitImpls: [RustTraitImplSyntax] = []
    /// Declaration heads recovered from a damaged C parse. These have no
    /// reliable body extent and are used only for named source navigation.
    var recoveredFunctionDeclarations: [DocumentSymbol] = []
}

/// One syntactic call: the whole site and, when the grammar names it, the
/// callee's name token. It is not an edge until the name resolves to a SCIP
/// occurrence. A site without a name (a parenthesized or computed callee,
/// `(f)(x)`) is kept so coverage can count it as unresolved rather than
/// silently omitting it.
struct CallSite: Equatable, Sendable {
    /// `call`, `macro`, or `dynamic` (no supported callee name). A macro's
    /// expansion is unknown, so it never proves anything about reachable
    /// operations.
    let kind: String
    let nameByteRange: Range<Int>?
    let byteRange: Range<Int>
    var isMacro: Bool { kind == "macro" }
    /// Where the site sits for ownership and ordering.
    var anchorByte: Int { nameByteRange?.lowerBound ?? byteRange.lowerBound }
}

struct SyntaxHighlight: Equatable, Sendable {
    let name: String
    let byteRange: Range<Int>
}

struct SourceFold: Equatable, Sendable, Identifiable {
    let kind: String
    let byteRange: Range<Int>
    var id: String { "\(kind):\(byteRange.lowerBound):\(byteRange.upperBound)" }
}

struct DocumentSymbol: Equatable, Sendable, Identifiable {
    let name: String
    let kind: String
    let byteRange: Range<Int>
    let selectionByteRange: Range<Int>
    let depth: Int
    var id: String { "\(kind):\(byteRange.lowerBound):\(byteRange.upperBound)" }
}

extension DocumentSymbol {
    /// Symbols directly contained by this declaration, in source order.
    func children(in symbols: [DocumentSymbol]) -> [DocumentSymbol] {
        symbols.filter { candidate in
            guard candidate.id != id,
                  byteRange.lowerBound <= candidate.byteRange.lowerBound,
                  candidate.byteRange.upperBound <= byteRange.upperBound else { return false }
            return !symbols.contains { intermediary in
                intermediary.id != id && intermediary.id != candidate.id
                    && byteRange.lowerBound <= intermediary.byteRange.lowerBound
                    && intermediary.byteRange.upperBound <= byteRange.upperBound
                    && intermediary.byteRange.lowerBound <= candidate.byteRange.lowerBound
                    && candidate.byteRange.upperBound <= intermediary.byteRange.upperBound
            }
        }
    }

    static func roots(in symbols: [DocumentSymbol]) -> [DocumentSymbol] {
        symbols.filter { candidate in
            !symbols.contains { possibleParent in
                possibleParent.id != candidate.id
                    && possibleParent.byteRange.lowerBound <= candidate.byteRange.lowerBound
                    && candidate.byteRange.upperBound <= possibleParent.byteRange.upperBound
            }
        }
    }
}

struct SourceScope: Equatable, Sendable {
    let kind: String
    let byteRange: Range<Int>
}

/// Drawing-only, function-local identifier matches used when SCIP cannot
/// describe inactive/configuration-gated source. This carries no semantic
/// identity and must never be used for definition or reference navigation.
struct SyntacticOccurrenceSelection: Equatable, Sendable {
    let scopeByteRange: Range<Int>
    let spelling: Data
    let activeByteRange: Range<Int>
    let byteRanges: [Range<Int>]
}

extension SyntaxSnapshot {
    func localIdentifierSelection(at byte: Int, in buffer: SourceBuffer) -> SyntacticOccurrenceSelection? {
        guard path == buffer.path,
              let scope = scopes.filter({ ["function", "closure"].contains($0.kind) && $0.byteRange.contains(byte) })
                .min(by: { $0.byteRange.count < $1.byteRange.count }),
              let active = identifierRange(at: byte, in: buffer.data, limitedTo: scope.byteRange),
              !isExcluded(active) else { return nil }
        let spelling = buffer.data[active]
        guard !spelling.isEmpty, spelling.first.map({ !$0.isASCIIDigit }) == true else { return nil }

        var ranges: [Range<Int>] = []
        var cursor = scope.byteRange.lowerBound
        while cursor < scope.byteRange.upperBound {
            guard isIdentifierByte(buffer.data[cursor]) else { cursor += 1; continue }
            let start = cursor
            while cursor < scope.byteRange.upperBound, isIdentifierByte(buffer.data[cursor]) { cursor += 1 }
            let range = start..<cursor
            if buffer.data[range].elementsEqual(spelling), !isExcluded(range) { ranges.append(range) }
        }
        guard !ranges.isEmpty else { return nil }
        return SyntacticOccurrenceSelection(scopeByteRange: scope.byteRange, spelling: Data(spelling),
                                            activeByteRange: active, byteRanges: ranges)
    }

    private func isExcluded(_ range: Range<Int>) -> Bool {
        highlights.contains { highlight in
            (highlight.name.hasPrefix("comment") || highlight.name.hasPrefix("string")
                || highlight.name.hasPrefix("number") || highlight.name.hasPrefix("keyword"))
                && highlight.byteRange.overlaps(range)
        }
    }

    private func identifierRange(at byte: Int, in data: Data, limitedTo scope: Range<Int>) -> Range<Int>? {
        guard byte >= scope.lowerBound, byte < scope.upperBound, byte < data.count,
              isIdentifierByte(data[byte]) else { return nil }
        var lower = byte
        var upper = byte + 1
        while lower > scope.lowerBound, isIdentifierByte(data[lower - 1]) { lower -= 1 }
        while upper < scope.upperBound, isIdentifierByte(data[upper]) { upper += 1 }
        return lower..<upper
    }

    private func isIdentifierByte(_ byte: UInt8) -> Bool {
        byte == 0x5F || byte >= 0x80 || (0x30...0x39).contains(byte)
            || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
    }
}

private extension UInt8 {
    var isASCIIDigit: Bool { (0x30...0x39).contains(self) }
}
