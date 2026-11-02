import Foundation

/// The innermost Tree-sitter declaration around the caret, plus the SCIP
/// symbol the index records at its name. Its identity, not the caret byte,
/// decides when the Context inspector's upper region refreshes.
struct DeclarationContext: Sendable, Equatable {
    struct Identity: Hashable, Sendable {
        let path: String
        let declarationID: String
        let source: SourceContentIdentity
        let symbol: SemanticSymbolID?
        let indexRevision: Int
    }

    enum Link: Sendable, Equatable {
        /// The index has a definition occurrence at the declaration's name.
        case defines(SemanticSymbolID)
        /// An `impl` block: the name is a real SCIP reference to the
        /// implemented type, so its references are that type's references.
        case implements(SemanticSymbolID)
        /// No indexed occurrence at the name (unindexed file, cfg-inactive
        /// code, or a construct the indexer does not name).
        case none

        var symbol: SemanticSymbolID? {
            switch self {
            case .defines(let symbol), .implements(let symbol): symbol
            case .none: nil
            }
        }
    }

    let identity: Identity
    let declaration: DocumentSymbol
    let path: String
    let line: Int
    /// Actual source from the declaration's start to its body, bounded.
    let signature: String
    let link: Link
    /// SCIP kind name when the index describes the symbol.
    let semanticKind: SemanticSymbolKind?

    var displayKind: String {
        if let semanticKind, semanticKind.rawValue != 0 { return semanticKind.name }
        return declaration.kind == "extension" ? "Implementation" : declaration.kind.capitalized
    }

    static let maxSignatureLines = 8
    static let maxSignatureBytes = 600
}

extension DeclarationContext {
    /// Innermost declaration containing the byte. Tree-sitter symbol ranges
    /// are half-open, so the byte after a closing brace is outside.
    static func innermostDeclaration(at byte: Int, in symbols: [DocumentSymbol]) -> DocumentSymbol? {
        var best: DocumentSymbol?
        for symbol in symbols where symbol.byteRange.contains(byte) {
            if best == nil || symbol.byteRange.count < best!.byteRange.count { best = symbol }
        }
        return best
    }

    /// The SCIP identity at a declaration's name. Never by spelling: only an
    /// occurrence the index places at the name's first byte counts.
    static func link(for declaration: DocumentSymbol, in semantics: DocumentSemantics?) -> Link {
        guard let semantics else { return .none }
        let start = declaration.selectionByteRange.lowerBound
        let hits = semantics.occurrences(at: start).filter {
            $0.range.startLine == $0.range.endLine && $0.byteRange.lowerBound == start
        }
        if let definition = hits.first(where: \.isDefinition) { return .defines(definition.symbol) }
        if declaration.kind == "extension", let reference = hits.first { return .implements(reference.symbol) }
        return .none
    }

    static func identity(path: String, declaration: DocumentSymbol, source: SourceContentIdentity, link: Link, indexRevision: Int) -> Identity {
        Identity(path: path, declarationID: declaration.id, source: source, symbol: link.symbol, indexRevision: indexRevision)
    }

    static func make(identity: Identity, declaration: DocumentSymbol, link: Link, buffer: SourceBuffer,
                     folds: [SourceFold], index: SemanticIndex) -> DeclarationContext {
        DeclarationContext(identity: identity, declaration: declaration, path: buffer.path,
                           line: buffer.line(atByte: declaration.selectionByteRange.lowerBound),
                           signature: signature(of: declaration, buffer: buffer, folds: folds), link: link,
                           semanticKind: link.symbol.flatMap { index.symbols[$0]?.kind })
    }

    /// Source text up to the declaration's body fold (its `{`, or an
    /// indentation body), else the declaration's first line. Bounded in lines
    /// and bytes; whitespace runs are kept as written.
    static func signature(of declaration: DocumentSymbol, buffer: SourceBuffer, folds: [SourceFold]) -> String {
        let start = declaration.byteRange.lowerBound
        let body = folds.lazy.filter {
            $0.byteRange.lowerBound >= declaration.selectionByteRange.upperBound
                && $0.byteRange.upperBound <= declaration.byteRange.upperBound
        }.map(\.byteRange.lowerBound).min()
        let line = buffer.line(atByte: start)
        let firstLineEnd = line < buffer.lineCount ? buffer.lineStarts[line] - 1 : buffer.data.count
        var end = body ?? max(firstLineEnd, declaration.selectionByteRange.upperBound)
        end = min(end, declaration.byteRange.upperBound, start + maxSignatureBytes)
        guard end > start else { return declaration.name }
        // Clamp a byte cap onto a scalar boundary.
        while end > start, end < buffer.data.count, buffer.data[end] & 0xC0 == 0x80 { end -= 1 }
        let text = String(decoding: buffer.data[start..<end], as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasSuffix("\r") ? $0.dropLast() : $0 }
        // Continuation lines carry the declaration's own indentation (it is
        // nested in an impl or module); remove it so the block reads flush.
        let lineStart = buffer.lineStarts[line - 1]
        let indent = buffer.data[lineStart..<start].allSatisfy { $0 == 0x20 || $0 == 0x09 }
            ? String(decoding: buffer.data[lineStart..<start], as: UTF8.self) : ""
        var kept = lines.prefix(maxSignatureLines).enumerated().map { offset, text in
            offset > 0 && !indent.isEmpty && text.hasPrefix(indent) ? String(text.dropFirst(indent.count)) : String(text)
        }
        while let last = kept.last, last.allSatisfy(\.isWhitespace) { kept.removeLast() }
        if let last = kept.indices.last { kept[last] = kept[last].replacing(/\s+$/, with: "") }
        let result = kept.joined(separator: "\n")
        return result.isEmpty ? declaration.name : result
    }
}
