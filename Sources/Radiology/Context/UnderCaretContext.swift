import Foundation

/// The SCIP occurrence under the caret and the metadata the index actually
/// records for its symbol. Its identity is the occurrence, so moving through
/// the characters of one token changes nothing.
struct UnderCaretContext: Sendable, Equatable {
    struct Identity: Hashable, Sendable {
        let path: String
        let source: SourceContentIdentity?
        let symbol: SemanticSymbolID
        let occurrence: Range<Int>
        let indexRevision: Int
        let documentRevision: Int
    }

    let identity: Identity
    let target: SemanticTarget
    /// SCIP `signature`, verbatim; empty when the indexer recorded none.
    let signature: String
    /// The first documentation paragraph, without code fences.
    let documentation: String?
    /// Every in-repository definition, including one under the caret.
    let definitions: [SemanticPosition]
    /// `scheme package version` of a symbol defined outside the repository.
    let externalPackage: String?
    /// Display name of SCIP's `enclosing_symbol`, when recorded.
    let enclosingName: String?
    /// Occurrences of this symbol in the current document.
    let fileOccurrenceCount: Int
    /// One-based line and text of the first definition when it is in the
    /// open file (always so for locals); quiet context without a fetch.
    let localDefinitionLine: SnippetLine?

    var symbol: SemanticSymbolID { target.symbol }
    var isLocal: Bool { target.symbol.isLocal }
    /// Calls and types get a prominent preview; locals stay quiet.
    var isProminent: Bool { !isLocal }
    /// The definition to preview and activate: never the one under the caret.
    var destination: SemanticPosition? { target.definitions.first }
    var isDefinedOutsideRepository: Bool { definitions.isEmpty && !isLocal }

    static let maxDocumentationLength = 280
}

extension UnderCaretContext {
    /// A semantic target worth describing, or nil for whitespace, keywords,
    /// imports, and anything the index has no single-line occurrence for.
    static func target(at byte: Int, in semantics: DocumentSemantics, index: SemanticIndex) -> SemanticTarget? {
        guard let target = index.target(in: semantics, at: byte) else { return nil }
        let isImport = semantics.occurrences(at: byte).contains {
            $0.byteRange == target.byteRange && $0.symbol == target.symbol && $0.roles & SCIPSymbolRole.import != 0
        }
        return isImport ? nil : target
    }

    static func identity(for target: SemanticTarget, path: String, source: SourceContentIdentity?,
                         indexRevision: Int, documentRevision: Int) -> Identity {
        Identity(path: path, source: source, symbol: target.symbol, occurrence: target.byteRange,
                 indexRevision: indexRevision, documentRevision: documentRevision)
    }

    static func make(identity: Identity, target: SemanticTarget, semantics: DocumentSemantics, index: SemanticIndex,
                     buffer: SourceBuffer) -> UnderCaretContext {
        let info = index.symbols[target.symbol]
        let definitions = index.definitions(of: target.symbol)
        let enclosing = info?.enclosingSymbol.isEmpty == false
            ? info.map { index.displayName(SemanticSymbolID(symbol: $0.enclosingSymbol, document: semantics.path)) }
            : nil
        let count = semantics.occurrences.count { $0.symbol == target.symbol && !$0.byteRange.isEmpty }
        let localLine = definitions.first { $0.path == buffer.path }
            .flatMap { buffer.byteRange(for: $0.range, encoding: $0.encoding) }
            .map { buffer.line(atByte: $0.lowerBound) }
            .map { SnippetLine(number: $0, text: buffer.displayLineText($0)) }
        return UnderCaretContext(identity: identity, target: target, signature: info?.signature ?? "",
                                 documentation: info.flatMap { firstParagraph(of: $0.documentation) },
                                 definitions: definitions,
                                 externalPackage: definitions.isEmpty && !target.symbol.isLocal
                                     ? SCIPSymbolString.package(of: target.symbol.symbol) : nil,
                                 enclosingName: enclosing, fileOccurrenceCount: count, localDefinitionLine: localLine)
    }

    /// Indexers often repeat the signature as a fenced code block; skip
    /// fences and return the first prose paragraph, bounded.
    static func firstParagraph(of documentation: [String]) -> String? {
        for entry in documentation {
            var inFence = false
            var paragraph: [Substring] = []
            for line in entry.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("```") { inFence.toggle(); continue }
                if inFence { continue }
                if trimmed.isEmpty {
                    if !paragraph.isEmpty { break }
                    continue
                }
                paragraph.append(line)
            }
            guard !paragraph.isEmpty else { continue }
            let text = paragraph.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            guard text.count > maxDocumentationLength else { return text }
            return String(text.prefix(maxDocumentationLength - 1)) + "…"
        }
        return nil
    }
}
