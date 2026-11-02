import Foundation

/// Occurrences of one loaded file converted to canonical byte ranges against
/// the actual bytes on screen. This is the only place SCIP coordinates meet
/// `SourceBuffer`; everything above works in bytes.
struct DocumentSemantics: Sendable, Equatable {
    struct Occurrence: Sendable, Equatable {
        let byteRange: Range<Int>
        /// The indexer's original coordinates, kept for matching definitions.
        let range: SCIPRange
        let symbol: SemanticSymbolID
        let roles: Int32
        var isDefinition: Bool { roles & SCIPSymbolRole.definition != 0 }
    }

    let path: String
    /// Sorted by start byte, then widest first.
    let occurrences: [Occurrence]
    /// Occurrences whose coordinates no longer fit the file: a sign the index
    /// predates the current contents.
    let unmappedCount: Int

    static func make(document: SemanticDocument, buffer: SourceBuffer) -> DocumentSemantics {
        var occurrences: [Occurrence] = []
        occurrences.reserveCapacity(document.occurrences.count)
        var unmapped = 0
        for occurrence in document.occurrences {
            guard let range = buffer.byteRange(for: occurrence.range, encoding: document.encoding) else {
                unmapped += 1
                continue
            }
            occurrences.append(Occurrence(byteRange: range, range: occurrence.range, symbol: occurrence.symbol, roles: occurrence.roles))
        }
        occurrences.sort { lhs, rhs in
            lhs.byteRange.lowerBound == rhs.byteRange.lowerBound
                ? lhs.byteRange.upperBound > rhs.byteRange.upperBound
                : lhs.byteRange.lowerBound < rhs.byteRange.lowerBound
        }
        return DocumentSemantics(path: document.path, occurrences: occurrences, unmappedCount: unmapped)
    }

    /// Occurrences containing the byte, narrowest first. Half-open: the byte
    /// just past an identifier belongs to whatever follows it.
    func occurrences(at byte: Int) -> [Occurrence] {
        var low = 0
        var high = occurrences.count
        while low < high {
            let middle = (low + high) / 2
            if occurrences[middle].byteRange.lowerBound <= byte { low = middle + 1 } else { high = middle }
        }
        var hits: [Occurrence] = []
        for index in stride(from: low - 1, through: 0, by: -1) {
            let occurrence = occurrences[index]
            if occurrence.byteRange.contains(byte) || (occurrence.byteRange.isEmpty && occurrence.byteRange.lowerBound == byte) {
                hits.append(occurrence)
            } else if occurrence.byteRange.upperBound < byte - 65_536 {
                break
            }
        }
        return hits.sorted { $0.byteRange.count < $1.byteRange.count }
    }
}

extension SourceBuffer {
    /// Converts a SCIP range to canonical bytes, or nil when either end falls
    /// outside the current file contents.
    func byteRange(for range: SCIPRange, encoding: ColumnEncoding) -> Range<Int>? {
        guard let start = byteOffset(zeroBasedLine: range.startLine, column: range.startCharacter, encoding: encoding),
              let end = byteOffset(zeroBasedLine: range.endLine, column: range.endCharacter, encoding: encoding),
              start <= end else { return nil }
        return start..<end
    }
}

/// What the reader can do with the symbol under a byte position.
struct SemanticTarget: Sendable, Equatable {
    let symbol: SemanticSymbolID
    let displayName: String
    let kind: SemanticSymbolKind
    /// The occurrence the caret is on.
    let byteRange: Range<Int>
    let isOnDefinition: Bool
    /// In-repository definitions, excluding the occurrence under the caret.
    let definitions: [SemanticPosition]
    let referenceCount: Int

    var hasDefinition: Bool { !definitions.isEmpty }
}

/// One explicitly selected semantic identity and all of its occurrences in
/// the currently mapped document. Ranges remain canonical UTF-8 bytes until
/// SourceViewer crosses the TextKit boundary.
struct SemanticOccurrenceSelection: Sendable, Equatable {
    let symbol: SemanticSymbolID
    let activeByteRange: Range<Int>
    let byteRanges: [Range<Int>]
}

extension SemanticIndex {
    /// Resolves the symbol under a byte position. With several occurrences at
    /// one place (Rust field shorthand binds a local and a field on the same
    /// identifier), the narrowest wins, then a navigable one, then a
    /// repository-wide symbol over a document-local one.
    func target(in semantics: DocumentSemantics, at byte: Int) -> SemanticTarget? {
        // Identifiers sit on one line. Multi-line occurrences, such as the
        // whole-file module definition rust-analyzer emits, are not caret targets.
        let hits = semantics.occurrences(at: byte).filter { $0.range.startLine == $0.range.endLine }
        guard !hits.isEmpty else { return nil }
        let candidates = hits.map { occurrence -> SemanticTarget in
            // The definition the caret already sits on is not a jump target.
            let here = SemanticPosition(path: semantics.path, range: occurrence.range, encoding: documents[semantics.path]?.encoding ?? .utf8)
            let definitions = definitions(of: occurrence.symbol).filter { !occurrence.isDefinition || $0 != here }
            return SemanticTarget(symbol: occurrence.symbol, displayName: displayName(occurrence.symbol),
                                  kind: symbols[occurrence.symbol]?.kind ?? SemanticSymbolKind(rawValue: 0),
                                  byteRange: occurrence.byteRange, isOnDefinition: occurrence.isDefinition,
                                  definitions: definitions, referenceCount: referenceCount(of: occurrence.symbol))
        }
        let narrowest = candidates[0].byteRange.count
        let tied = candidates.filter { $0.byteRange.count == narrowest }
        return tied.first { $0.hasDefinition && !$0.symbol.isLocal }
            ?? tied.first { $0.hasDefinition }
            ?? tied.first { !$0.symbol.isLocal }
            ?? tied.first
    }

    /// Selects by SCIP identity, never by spelling. This deliberately includes
    /// definition and reference roles, and also works for symbols whose
    /// definition lives outside the repository.
    func occurrenceSelection(in semantics: DocumentSemantics, at byte: Int) -> SemanticOccurrenceSelection? {
        guard let target = target(in: semantics, at: byte) else { return nil }
        var seen = Set<Range<Int>>()
        let ranges = semantics.occurrences.reduce(into: [Range<Int>]()) { ranges, occurrence in
            guard occurrence.symbol == target.symbol, !occurrence.byteRange.isEmpty,
                  seen.insert(occurrence.byteRange).inserted else { return }
            ranges.append(occurrence.byteRange)
        }
        guard !ranges.isEmpty else { return nil }
        return SemanticOccurrenceSelection(symbol: target.symbol, activeByteRange: target.byteRange,
                                           byteRanges: ranges)
    }
}
