import Foundation

/// One numbered source line for a bounded sidebar preview.
struct SnippetLine: Sendable, Equatable, Identifiable {
    let number: Int
    let text: String
    var id: Int { number }
}

/// One reference occurrence, already converted to bytes against the file as
/// it is on disk now, with the line it sits on and a few lines of context for
/// the sidebar's call-site preview.
struct ReferenceHit: Sendable, Equatable, Identifiable {
    let location: SourceLocation
    let byteRange: Range<Int>
    let line: Int
    let column: Int
    let lineText: String
    /// `lineText` split around the occurrence on canonical byte boundaries;
    /// leading indentation is dropped from `leading` for display.
    let leading: String
    let match: String
    let trailing: String
    /// Up to `contextRadius` lines either side of `line`, including it.
    let context: [SnippetLine]
    let isDefinition: Bool
    var id: String { "\(location.path):\(byteRange.lowerBound)" }

    static let contextRadius = 2
}

struct ReferenceGroup: Sendable, Equatable, Identifiable {
    let path: String
    let hits: [ReferenceHit]
    var id: String { path }
}

struct ReferenceResults: Sendable, Equatable {
    let symbol: SemanticSymbolID
    let displayName: String
    let kind: SemanticSymbolKind
    let groups: [ReferenceGroup]
    /// Occurrences whose coordinates no longer fit the current file contents.
    let unmappedCount: Int
    /// Files the index names that could not be read.
    let unreadablePaths: [String]
    /// Every listed hit, definitions included.
    var total: Int { groups.reduce(0) { $0 + $1.hits.count } }
    /// Listed hits that are uses, not definitions. This is the honest
    /// "references" count; definitions are labelled separately.
    var referenceCount: Int { groups.reduce(0) { $0 + $1.hits.count { !$0.isDefinition } } }
    var definitionCount: Int { total - referenceCount }
    var fileCount: Int { groups.count }
    func hit(id: ReferenceHit.ID) -> ReferenceHit? {
        for group in groups { if let hit = group.hits.first(where: { $0.id == id }) { return hit } }
        return nil
    }
}

/// Queries that touch the disk or scan the whole index run here, off MainActor.
actor SemanticQueryWorker {
    private let sources = SourceStore()
    private let syntax = SyntaxWorker()
    /// Recently parsed preview destinations, keyed by path and exact bytes,
    /// so previewing several symbols of one file parses it once.
    private var structure = BoundedCache<StructureKey, SyntaxSnapshot>(capacity: 4)

    private struct StructureKey: Hashable {
        let path: String
        let content: SourceContentIdentity
    }

    func documentSemantics(index: SemanticIndex, buffer: SourceBuffer) -> DocumentSemantics? {
        guard let document = index.documents[buffer.path] else { return nil }
        return DocumentSemantics.make(document: document, buffer: buffer)
    }

    /// Resolves a definition's coordinates against the destination file.
    func resolve(_ position: SemanticPosition, root: URL) async throws -> SourceLocation {
        let buffer = try await sources.load(root: root, path: position.path)
        guard let byte = buffer.byteOffset(zeroBasedLine: position.range.startLine, column: position.range.startCharacter, encoding: position.encoding) else {
            throw BrowserError.message("The index points at line \(position.range.startLine + 1) of \(position.path), which no longer matches the file. Reindex to refresh semantic data.")
        }
        return SourceLocation(path: position.path, byteOffset: byte)
    }

    /// Definitions and references of a symbol, grouped by file in path order.
    func references(of id: SemanticSymbolID, in index: SemanticIndex, root: URL) async throws -> ReferenceResults {
        var positions: [String: [(SemanticPosition, Bool)]] = [:]
        for position in index.definitions(of: id) { positions[position.path, default: []].append((position, true)) }
        for position in index.references[id] ?? [] { positions[position.path, default: []].append((position, false)) }
        var groups: [ReferenceGroup] = []
        var unmapped = 0
        var unreadable: [String] = []
        for path in positions.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            try Task.checkCancellation()
            guard let buffer = try? await sources.load(root: root, path: path) else {
                unreadable.append(path)
                continue
            }
            var hits: [ReferenceHit] = []
            for (position, isDefinition) in positions[path] ?? [] {
                guard let range = buffer.byteRange(for: position.range, encoding: position.encoding) else { unmapped += 1; continue }
                hits.append(Self.hit(in: buffer, range: range, isDefinition: isDefinition))
            }
            hits.sort { $0.byteRange.lowerBound < $1.byteRange.lowerBound }
            if !hits.isEmpty { groups.append(ReferenceGroup(path: path, hits: hits)) }
        }
        return ReferenceResults(symbol: id, displayName: index.displayName(id), kind: index.symbols[id]?.kind ?? SemanticSymbolKind(rawValue: 0),
                                groups: groups, unmappedCount: unmapped, unreadablePaths: unreadable)
    }

    /// A bounded definition preview read from disk, or nil when the position
    /// no longer maps onto the file. The destination is parsed here, off the
    /// main actor, so the excerpt ends with its Tree-sitter declaration even
    /// when the next item follows without a blank line. Unsupported or
    /// unparsable files fall back to the blank-line bound.
    func definitionPreview(at position: SemanticPosition, root: URL, maxLines: Int) async throws -> DefinitionPreview? {
        let buffer = try await sources.load(root: root, path: position.path)
        try Task.checkCancellation()
        guard let range = buffer.byteRange(for: position.range, encoding: position.encoding) else { return nil }
        let snapshot = try await structure(of: buffer)
        try Task.checkCancellation()
        return DefinitionPreview.make(buffer: buffer, startByte: range.lowerBound,
                                      declarationEnd: DefinitionPreview.declarationEnd(at: range.lowerBound, in: snapshot),
                                      maxLines: maxLines)
    }

    private func structure(of buffer: SourceBuffer) async throws -> SyntaxSnapshot? {
        let key = StructureKey(path: buffer.path, content: SourceContentIdentity(buffer.data))
        if let cached = structure[key] { return cached }
        do {
            guard let snapshot = try await syntax.parse(buffer) else { return nil }
            structure[key] = snapshot
            return snapshot
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    /// Builds a display-ready hit. Text is bounded: a very long line is
    /// windowed around the occurrence so the match itself stays visible.
    static func hit(in buffer: SourceBuffer, range: Range<Int>, isDefinition: Bool) -> ReferenceHit {
        let line = buffer.line(atByte: range.lowerBound)
        let lineBytes = buffer.lineByteRange(line)
        let limit = SourceBuffer.displayLineLimit
        // Occurrences may span lines; only the part on this line is emphasized.
        let lower = min(max(range.lowerBound, lineBytes.lowerBound), lineBytes.upperBound)
        let upper = min(max(lower, range.upperBound), lineBytes.upperBound, lower + limit)
        let windowStart = lineBytes.count <= limit ? lineBytes.lowerBound
            : buffer.scalarBoundary(atOrBefore: max(lineBytes.lowerBound, lower - limit / 4), floor: lineBytes.lowerBound)
        let windowEnd = lineBytes.count <= limit ? lineBytes.upperBound
            : buffer.scalarBoundary(atOrBefore: min(lineBytes.upperBound, max(upper, windowStart + limit)), floor: upper)
        func text(_ bytes: Range<Int>) -> String { String(decoding: buffer.data[bytes], as: UTF8.self) }
        var leading = text(windowStart..<lower)
        if windowStart > lineBytes.lowerBound { leading = "…" + leading } else { leading = String(leading.drop { $0 == " " || $0 == "\t" }) }
        var trailing = text(upper..<max(upper, windowEnd))
        if windowEnd < lineBytes.upperBound { trailing += "…" }
        let context = (max(1, line - ReferenceHit.contextRadius)...min(buffer.lineCount, line + ReferenceHit.contextRadius))
            .map { SnippetLine(number: $0, text: buffer.displayLineText($0)) }
        return ReferenceHit(location: SourceLocation(path: buffer.path, byteOffset: range.lowerBound), byteRange: range,
                            line: line, column: lower - lineBytes.lowerBound + 1, lineText: buffer.displayLineText(line),
                            leading: leading, match: text(lower..<upper), trailing: trailing,
                            context: context, isDefinition: isDefinition)
    }

    func search(_ query: String, in index: SemanticIndex) -> [SymbolSearch.Match] {
        SymbolSearch.rank(query, in: index.searchEntries)
    }
}
