import Foundation

/// A position in an indexed document, still in the indexer's line/column
/// coordinates. It becomes a canonical byte offset only against the actual file
/// contents, through `SourceBuffer`.
struct SemanticPosition: Hashable, Sendable {
    let path: String
    let range: SCIPRange
    let encoding: ColumnEncoding
}

/// The indexer's enclosing range of a definition: the whole item, in the
/// indexer's coordinates. It bounds a body; it is never an edge.
struct SemanticExtent: Sendable, Equatable {
    let path: String
    let range: SCIPRange
    let encoding: ColumnEncoding
}

struct SemanticOccurrence: Sendable, Equatable {
    let range: SCIPRange
    let symbol: SemanticSymbolID
    let roles: Int32
    var isDefinition: Bool { roles & SCIPSymbolRole.definition != 0 }
    var isImport: Bool { roles & SCIPSymbolRole.import != 0 }
}

struct SemanticDocument: Sendable {
    let path: String
    let language: String
    let encoding: ColumnEncoding
    /// Sorted by start line, then start column, then widest span first.
    let occurrences: [SemanticOccurrence]
}

/// One tool's contribution to a merged index.
struct SemanticIndexSource: Sendable, Equatable, Codable {
    let toolName: String
    let toolVersion: String
    let documentCount: Int
}

/// The normalized, immutable semantic model the application queries. It is
/// built off the main actor from one or more decoded SCIP indexes.
final class SemanticIndex: Sendable {
    let documents: [String: SemanticDocument]
    let symbols: [SemanticSymbolID: SemanticSymbol]
    let definitions: [SemanticSymbolID: [SemanticPosition]]
    let references: [SemanticSymbolID: [SemanticPosition]]
    /// The first definition's `enclosing_range` per symbol, when the indexer
    /// recorded one (rust-analyzer does for every definition).
    let definitionExtents: [SemanticSymbolID: SemanticExtent]
    let sources: [SemanticIndexSource]
    /// Repository symbols with at least one in-repository definition, for ⌘T.
    let searchEntries: [SymbolSearchEntry]
    let traitImplementations: TraitImplementationIndex

    var documentCount: Int { documents.count }
    var symbolCount: Int { symbols.count }

    static let empty = SemanticIndex(indexes: [])

    /// A decoded index plus the repository-relative directory it was generated
    /// from, so documents of a nested project map back to repository paths.
    struct Input: Sendable {
        let index: SCIPIndex
        let pathPrefix: String
        let defaultEncoding: ColumnEncoding?
        init(index: SCIPIndex, projectDirectory: String = "", defaultEncoding: ColumnEncoding? = nil) {
            self.index = index
            pathPrefix = projectDirectory.isEmpty ? "" : projectDirectory + "/"
            self.defaultEncoding = defaultEncoding
        }
    }

    convenience init(indexes: [SCIPIndex]) {
        self.init(inputs: indexes.map { Input(index: $0) })
    }

    init(inputs: [Input]) {
        var documents: [String: SemanticDocument] = [:]
        var symbols: [SemanticSymbolID: SemanticSymbol] = [:]
        var definitions: [SemanticSymbolID: [SemanticPosition]] = [:]
        var references: [SemanticSymbolID: [SemanticPosition]] = [:]
        var extents: [SemanticSymbolID: SemanticExtent] = [:]
        var sources: [SemanticIndexSource] = []
        for input in inputs {
            let index = input.index
            sources.append(SemanticIndexSource(toolName: index.metadata.toolName, toolVersion: index.metadata.toolVersion,
                                               documentCount: index.documents.count))
            // TextDocumentEncoding describes file bytes, not occurrence columns.
            // Compiler indexers can use UTF-16 columns in UTF-8 source files and
            // omit Document.position_encoding. Prefer the adapter's contract.
            let fallbackEncoding = input.defaultEncoding
                ?? Self.encoding(fromPositionEncoding: 0, textEncoding: index.metadata.textDocumentEncoding)
            for external in index.externalSymbols where !external.symbol.isEmpty {
                let id = SemanticSymbolID(symbol: external.symbol, document: "")
                guard !id.isLocal, symbols[id] == nil else { continue }
                symbols[id] = Self.symbol(external, id: id)
            }
            for document in index.documents {
                guard let path = Self.validatedPath(input.pathPrefix + document.relativePath) else { continue }
                let encoding = Self.encoding(fromPositionEncoding: document.positionEncoding, textEncoding: 0) ?? fallbackEncoding ?? .utf8
                for info in document.symbols where !info.symbol.isEmpty {
                    let id = SemanticSymbolID(symbol: info.symbol, document: path)
                    // A later, richer record (one with a display name) replaces a bare one.
                    if let existing = symbols[id], !existing.displayName.isEmpty, info.displayName.isEmpty { continue }
                    symbols[id] = Self.symbol(info, id: id)
                }
                var occurrences: [SemanticOccurrence] = []
                occurrences.reserveCapacity(document.occurrences.count)
                for raw in document.occurrences {
                    guard let range = raw.range, range.isWellFormed, !raw.symbol.isEmpty else { continue }
                    let id = SemanticSymbolID(symbol: raw.symbol, document: path)
                    occurrences.append(SemanticOccurrence(range: range, symbol: id, roles: raw.symbolRoles))
                    let position = SemanticPosition(path: path, range: range, encoding: encoding)
                    if raw.isDefinition {
                        definitions[id, default: []].append(position)
                        if extents[id] == nil, let enclosing = raw.enclosingRange, enclosing.isWellFormed {
                            extents[id] = SemanticExtent(path: path, range: enclosing, encoding: encoding)
                        }
                    } else {
                        references[id, default: []].append(position)
                    }
                }
                occurrences.sort { lhs, rhs in
                    if lhs.range.startLine != rhs.range.startLine { return lhs.range.startLine < rhs.range.startLine }
                    if lhs.range.startCharacter != rhs.range.startCharacter { return lhs.range.startCharacter < rhs.range.startCharacter }
                    if lhs.range.endLine != rhs.range.endLine { return lhs.range.endLine > rhs.range.endLine }
                    return lhs.range.endCharacter > rhs.range.endCharacter
                }
                if let existing = documents[path] {
                    // Two indexers describing one file (mixed strategies): merge occurrences.
                    let merged = (existing.occurrences + occurrences).sorted { lhs, rhs in
                        (lhs.range.startLine, lhs.range.startCharacter) < (rhs.range.startLine, rhs.range.startCharacter)
                    }
                    documents[path] = SemanticDocument(path: path, language: existing.language, encoding: existing.encoding, occurrences: merged)
                } else {
                    documents[path] = SemanticDocument(path: path, language: document.language, encoding: encoding, occurrences: occurrences)
                }
            }
        }
        // Symbols that only appear in occurrences still deserve a name.
        for id in Set(definitions.keys).union(references.keys) where symbols[id] == nil {
            symbols[id] = SemanticSymbol(id: id, displayName: SCIPSymbolString.fallbackName(for: id.symbol),
                                         kind: SemanticSymbolKind(rawValue: 0), signature: "", documentation: [],
                                         enclosingSymbol: "", relationships: [])
        }
        self.documents = documents
        self.symbols = symbols
        self.definitions = definitions
        self.references = references
        definitionExtents = extents
        self.sources = sources
        searchEntries = definitions.compactMap { id, positions -> SymbolSearchEntry? in
            guard !id.isLocal, let symbol = symbols[id], let first = positions.min(by: { ($0.path, $0.range.startLine) < ($1.path, $1.range.startLine) }) else { return nil }
            let name = symbol.displayName.isEmpty ? SCIPSymbolString.fallbackName(for: id.symbol) : symbol.displayName
            guard !name.isEmpty else { return nil }
            return SymbolSearchEntry(id: id, name: name, kind: symbol.kind, position: first, definitionCount: positions.count)
        }.sorted { ($0.name, $0.position.path, $0.position.range.startLine) < ($1.name, $1.position.path, $1.position.range.startLine) }
        traitImplementations = .unavailable
    }

    /// Shares immutable semantic maps while attaching precomputed source impls.
    init(base: SemanticIndex, traitImplementations: TraitImplementationIndex) {
        documents = base.documents
        symbols = base.symbols
        definitions = base.definitions
        references = base.references
        definitionExtents = base.definitionExtents
        sources = base.sources
        searchEntries = base.searchEntries
        self.traitImplementations = traitImplementations
    }

    // MARK: - Queries

    func symbol(_ id: SemanticSymbolID) -> SemanticSymbol? { symbols[id] }

    func displayName(_ id: SemanticSymbolID) -> String {
        let name = symbols[id]?.displayName ?? ""
        return name.isEmpty ? SCIPSymbolString.fallbackName(for: id.symbol) : name
    }

    /// Definitions of a symbol inside the repository. A symbol without its own
    /// definition occurrence follows `Relationship.is_definition` once.
    func definitions(of id: SemanticSymbolID) -> [SemanticPosition] {
        if let direct = definitions[id], !direct.isEmpty { return direct }
        guard let symbol = symbols[id] else { return [] }
        return symbol.relationships.filter(\.isDefinition).flatMap { relationship in
            definitions[SemanticSymbolID(symbol: relationship.symbol, document: id.document ?? "")] ?? []
        }
    }

    func referenceCount(of id: SemanticSymbolID) -> Int { references[id]?.count ?? 0 }

    /// Occurrences whose half-open range contains the position, narrowest first.
    func occurrences(in path: String, atLine line: Int, column: Int) -> [SemanticOccurrence] {
        guard let document = documents[path] else { return [] }
        let occurrences = document.occurrences
        // Binary search to the first occurrence starting after this line, then
        // scan back: multi-line ranges may begin far earlier.
        var low = 0
        var high = occurrences.count
        while low < high {
            let middle = (low + high) / 2
            if occurrences[middle].range.startLine <= line { low = middle + 1 } else { high = middle }
        }
        var hits: [SemanticOccurrence] = []
        for index in stride(from: low - 1, through: 0, by: -1) {
            let occurrence = occurrences[index]
            if occurrence.range.startLine < line - 512 { break }
            if Self.range(occurrence.range, contains: line, column) { hits.append(occurrence) }
        }
        return hits.sorted { Self.span($0.range) < Self.span($1.range) }
    }

    private static func range(_ range: SCIPRange, contains line: Int, _ column: Int) -> Bool {
        if line < range.startLine || line > range.endLine { return false }
        if line == range.startLine, column < range.startCharacter { return false }
        if line == range.endLine, column >= range.endCharacter {
            // An empty range is a point; treat the point itself as a hit.
            return range.startLine == range.endLine && range.startCharacter == range.endCharacter && column == range.endCharacter
        }
        return true
    }

    private static func span(_ range: SCIPRange) -> (Int, Int) {
        (range.endLine - range.startLine, range.endLine == range.startLine ? range.endCharacter - range.startCharacter : range.endCharacter + 1_000_000)
    }

    private static func validatedPath(_ path: String) -> String? {
        guard !path.isEmpty, !path.hasPrefix("/") else { return nil }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
        return path
    }

    private static func encoding(fromPositionEncoding position: Int, textEncoding: Int) -> ColumnEncoding? {
        switch position {
        case 1: return .utf8
        case 2: return .utf16
        case 3: return .utf32
        default: break
        }
        switch textEncoding {
        case 1: return .utf8
        case 2: return .utf16
        default: return nil
        }
    }

    private static func symbol(_ info: SCIPSymbolInformation, id: SemanticSymbolID) -> SemanticSymbol {
        SemanticSymbol(id: id, displayName: info.displayName, kind: SemanticSymbolKind(rawValue: info.kind),
                       signature: info.signature, documentation: info.documentation,
                       enclosingSymbol: info.enclosingSymbol, relationships: info.relationships)
    }
}

struct SymbolSearchEntry: Sendable, Equatable, Identifiable {
    let id: SemanticSymbolID
    let name: String
    let kind: SemanticSymbolKind
    let position: SemanticPosition
    let definitionCount: Int
}
