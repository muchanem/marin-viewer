import Foundation

/// Traces incoming calls from exact SCIP identities and parsed call sites.
/// All traversal state belongs to one request: cancellation or switching
/// repositories cannot populate another request with old files or edges.
actor ReferenceCallTreeWorker {
    private struct File {
        let buffer: SourceBuffer
        let syntax: SyntaxSnapshot?
        let semantics: DocumentSemantics?
    }

    private struct Owner {
        let symbol: SemanticSymbolID?
        let name: String
        let location: SourceLocation
        let line: Int
        let boundary: String?
        /// The declaration's canonical name position distinguishes functions
        /// with the same label and unifies alternate identities at one body.
        let declaration: SourceLocation?
    }

    private struct Pending {
        let owner: Owner
        let depth: Int
        let ancestors: Set<SemanticSymbolID>
        let ancestorDeclarations: Set<SourceLocation>
    }

    private let sources = SourceStore()
    private let syntax = SyntaxWorker()

    /// Iterative depth-first traversal keeps every branch, including repeated
    /// callers reached by different paths. Cycles stop only the current path.
    /// A row budget bounds initial work; the UI can request a larger budget
    /// without a depth limit or silently dropping the remaining branches.
    func trace(_ hit: ReferenceHit, index: SemanticIndex, root: URL, budget: Int = 256) async throws -> ReferenceCallTree {
        var files = BoundedCache<String, File>(capacity: 48)
        var incoming: [SemanticSymbolID: [Owner]] = [:]
        var notices: Set<String> = []
        let file = try await load(hit.location.path, root: root, index: index, files: &files)
        if file.syntax?.hasParseErrors == true { notices.insert("\(hit.location.path): parse errors") }
        guard hit.byteRange.upperBound <= file.buffer.data.count,
              SemanticQueryWorker.hit(in: file.buffer, range: hit.byteRange, isDefinition: hit.isDefinition).match == hit.match else {
            throw BrowserError.message("This reference changed on disk. Reload or reindex to trace its callers.")
        }
        let first = owner(at: hit.location.byteOffset, in: file)
        var pending = [Pending(owner: first, depth: 0, ancestors: [], ancestorDeclarations: [])]
        var rows: [ReferenceCaller] = []
        let budget = max(1, budget)
        while !pending.isEmpty, rows.count < budget {
            try Task.checkCancellation()
            guard let next = pending.popLast() else { break }
            let owner = next.owner
            var note = owner.boundary
            if note == nil, let symbol = owner.symbol {
                let callers: [Owner]
                if let cached = incoming[symbol] {
                    callers = cached
                } else {
                    callers = try await self.callers(of: symbol, root: root, index: index, files: &files, notices: &notices)
                    incoming[symbol] = callers
                }
                if callers.isEmpty { note = "No indexed callers" }
                let ancestors = next.ancestors.union([symbol])
                let declarations = next.ancestorDeclarations.union(owner.declaration.map { [$0] } ?? [])
                let continuations = callers.filter { caller in
                    let repeatsSymbol = caller.symbol.map { ancestors.contains($0) } ?? false
                    let repeatsDeclaration = caller.declaration.map { declarations.contains($0) } ?? false
                    if repeatsSymbol || repeatsDeclaration {
                        note = "Recursive branch stopped"
                        return false
                    }
                    return true
                }
                // Stop before enqueueing a repeated function. Rendering it as
                // a terminal row still made the visible chain look cyclic.
                pending.append(contentsOf: continuations.reversed().map {
                    Pending(owner: $0, depth: next.depth + 1, ancestors: ancestors, ancestorDeclarations: declarations)
                })
            }
            rows.append(ReferenceCaller(id: rows.count, depth: next.depth, symbol: owner.symbol, name: owner.name,
                                        location: owner.location, line: owner.line, note: note))
        }
        return ReferenceCallTree(callers: rows, notices: notices.sorted(), hasMore: !pending.isEmpty, budget: budget)
    }

    private func callers(of symbol: SemanticSymbolID, root: URL, index: SemanticIndex,
                         files: inout BoundedCache<String, File>, notices: inout Set<String>) async throws -> [Owner] {
        let positions = (index.references[symbol] ?? []).sorted {
            ($0.path, $0.range.startLine, $0.range.startCharacter) < ($1.path, $1.range.startLine, $1.range.startCharacter)
        }
        var result: [Owner] = []
        var seen: Set<SourceLocation> = []
        for position in positions {
            try Task.checkCancellation()
            let file: File
            do {
                file = try await load(position.path, root: root, index: index, files: &files)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                notices.insert("\(position.path): file could not be read")
                continue
            }
            guard let range = file.buffer.byteRange(for: position.range, encoding: position.encoding) else {
                notices.insert("\(position.path): stale index coordinates")
                continue
            }
            let caller = owner(at: range.lowerBound, in: file)
            guard seen.insert(caller.location).inserted else { continue }
            if file.syntax?.hasParseErrors == true { notices.insert("\(position.path): parse errors") }
            guard let snapshot = file.syntax, snapshot.supportsCallSites, let semantics = file.semantics else {
                result.append(Owner(symbol: caller.symbol, name: caller.name, location: caller.location, line: caller.line,
                                    boundary: "Call-site structure unavailable", declaration: caller.declaration))
                continue
            }
            // A callback/alias/import is a reference, but proves no invocation.
            // Show it as a boundary instead of inventing an incoming call edge.
            guard snapshot.callSites.contains(where: {
                $0.nameByteRange?.lowerBound == range.lowerBound && CallGraphWorker.resolve($0, in: semantics) == symbol
            }) else {
                result.append(Owner(symbol: caller.symbol, name: caller.name, location: caller.location, line: caller.line,
                                    boundary: "Non-call reference; invocation unknown", declaration: caller.declaration))
                continue
            }
            result.append(caller)
        }
        return result
    }

    private func owner(at byte: Int, in file: File) -> Owner {
        let location = SourceLocation(path: file.buffer.path, byteOffset: byte)
        let line = file.buffer.line(atByte: byte)
        guard let snapshot = file.syntax else {
            return Owner(symbol: nil, name: "Reference", location: location, line: line, boundary: "No parsed structure", declaration: nil)
        }
        let callable = snapshot.symbols.filter {
            SyntaxSnapshot.callableKinds.contains($0.kind) && $0.byteRange.contains(byte)
        }.min { $0.byteRange.count < $1.byteRange.count }
        let closure = snapshot.scopes.filter { $0.kind == "closure" && $0.byteRange.contains(byte) }
            .min { $0.byteRange.count < $1.byteRange.count }
        if let closure, callable == nil || closure.byteRange.count < (callable?.byteRange.count ?? Int.max) {
            return Owner(symbol: nil, name: callable.map { "Closure in \($0.name)" } ?? "Closure", location: location,
                         line: line, boundary: "Closure invocation is not indexed", declaration: nil)
        }
        guard let callable else {
            return Owner(symbol: nil, name: "Top level", location: location, line: line, boundary: "No enclosing callable", declaration: nil)
        }
        let symbol = DeclarationContext.link(for: callable, in: file.semantics).symbol
        return Owner(symbol: symbol, name: callable.name, location: location, line: line,
                     boundary: symbol == nil ? "Callable is not indexed" : nil,
                     declaration: location.with(byteOffset: callable.selectionByteRange.lowerBound))
    }

    private func load(_ path: String, root: URL, index: SemanticIndex, files: inout BoundedCache<String, File>) async throws -> File {
        if let cached = files[path] { return cached }
        let buffer = try await sources.load(root: root, path: path)
        let snapshot: SyntaxSnapshot?
        do { snapshot = try await syntax.parse(buffer) }
        catch is CancellationError { throw CancellationError() }
        catch { snapshot = nil }
        try Task.checkCancellation()
        let semantics = index.documents[path].map { DocumentSemantics.make(document: $0, buffer: buffer) }
        let loaded = File(buffer: buffer, syntax: snapshot, semantics: semantics)
        files[path] = loaded
        return loaded
    }
}
