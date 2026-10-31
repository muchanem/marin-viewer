import Foundation

/// Resolves declarations in the actual source bytes, independently of index
/// availability or stale line coordinates. Ambiguous names never pick a winner.
enum CodePathSymbolResolver {
    static func resolve(_ name: String, in buffer: SourceBuffer, syntax: SyntaxSnapshot?) throws -> Int {
        try destinations(name, in: buffer, syntax: syntax)[0]
    }

    static func destinations(_ name: String, in buffer: SourceBuffer, syntax: SyntaxSnapshot?) throws -> [Int] {
        if let syntax {
            let selector = compact(name)
            let recovered = syntax.recoveredFunctionDeclarations.filter { candidate in
                !syntax.symbols.contains { $0.selectionByteRange == candidate.selectionByteRange }
            }
            var matches = (syntax.symbols + recovered).filter { symbol in
                var names = [symbol.name]
                let parents = syntax.symbols.filter {
                    $0.id != symbol.id && $0.byteRange.lowerBound <= symbol.byteRange.lowerBound
                        && $0.byteRange.upperBound >= symbol.byteRange.upperBound
                }.sorted { $0.byteRange.count > $1.byteRange.count }.map(\.name)
                for start in parents.indices {
                    names.append((Array(parents[start...]) + [symbol.name]).joined(separator: "::"))
                    names.append((Array(parents[start...]) + [symbol.name]).joined(separator: "."))
                }
                // An out-of-class C++ definition carries its qualifier before
                // the captured terminal name rather than in an enclosing node.
                let prefix = String(decoding: buffer.data[symbol.byteRange.lowerBound..<symbol.selectionByteRange.lowerBound], as: UTF8.self)
                if let qualifier = prefix.split(whereSeparator: \.isWhitespace).last, qualifier.hasSuffix("::") {
                    names.append(String(qualifier) + symbol.name)
                    for start in parents.indices {
                        names.append(Array(parents[start...]).joined(separator: "::") + "::" + qualifier + symbol.name)
                    }
                }
                if names.contains(where: { compact($0) == selector }) { return true }
                // Exact declaration headers let callers distinguish overloads.
                let declaration = String(decoding: buffer.data[symbol.byteRange], as: UTF8.self)
                let header = declaration.prefix { $0 != "{" && $0 != ";" && (syntax.languageID != "python" || $0 != "\n") }
                return name.contains("(") && compact(String(header)) == selector
            }
            if matches.count > 1 {
                let definitions = matches.filter { symbol in
                    syntax.scopes.contains { $0.kind == "function" && $0.byteRange.upperBound == symbol.byteRange.upperBound }
                        || syntax.recoveredFunctionDeclarations.contains { $0.selectionByteRange == symbol.selectionByteRange }
                }
                if !definitions.isEmpty { matches = definitions }
            }
            let positions = matches.map(\.selectionByteRange.lowerBound).sorted()
            if positions.count == 1 { return positions }
            if ["c", "cpp"].contains(syntax.languageID),
               matches.allSatisfy({ SyntaxSnapshot.callableKinds.contains($0.kind) }),
               CodePathSourceText.areConditionalAlternatives(positions, in: buffer) { return positions }
            if matches.count > 1 {
                throw BrowserError.message("‘\(name)’ is ambiguous in \(buffer.path). Use an enclosing type/module name or the exact declaration header to distinguish it.")
            }
        } else if ["s", "asm"].contains(URL(filePath: buffer.path).pathExtension.lowercased()) {
            let bytes = CodePathSourceText.masked(buffer.data)
            let macro = try NSRegularExpression(pattern: #"^\s*(?:BEGIN_FUNC|ENTRY|ENTRY_NP|SYM_FUNC_START|SYM_CODE_START)\s*\(\s*([A-Za-z_.$][A-Za-z0-9_.$]*)\s*\)"#)
            var matches: [Int] = []
            for (index, start) in buffer.lineStarts.enumerated() {
                let end = index + 1 < buffer.lineCount ? buffer.lineStarts[index + 1] : buffer.data.count
                let line = String(decoding: bytes[start..<end], as: UTF8.self)
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix(name + ":") {
                    matches.append(start + line.prefix(while: \.isWhitespace).utf8.count)
                } else if let match = macro.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                          let range = Range(match.range(at: 1), in: line), String(line[range]) == name {
                    matches.append(start + line[..<range.lowerBound].utf8.count)
                }
            }
            if matches.count == 1 { return matches }
            if CodePathSourceText.areConditionalAlternatives(matches, in: buffer) { return matches }
            if matches.count > 1 { throw BrowserError.message("‘\(name)’ names more than one assembly label in \(buffer.path).") }
        } else {
            throw BrowserError.message("Symbol navigation is not supported for \(buffer.path). Use a file with parsed declarations or an assembly label.")
        }
        throw BrowserError.message("‘\(name)’ was not found in \(buffer.path) in this revision. Update the trace if the symbol was renamed or moved.")
    }

    private static func compact(_ value: String) -> String { value.filter { !$0.isWhitespace } }
}
