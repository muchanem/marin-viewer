import Foundation

/// Which callable owns a call site. Ownership is lexical: the innermost
/// function or closure scope containing the site. A site inside a closure or
/// a nested named function belongs to that node, never to the enclosing
/// named function, because whether and when it runs is unknown there.
struct ConditionalCallable: Equatable, Sendable {
    enum Kind: String, Sendable { case closure, function }
    let kind: Kind
    /// The nested named function's name, nil for a closure.
    let name: String?
    let byteRange: Range<Int>
    /// Sites owned directly by this node (not by callables nested in it).
    let siteCount: Int
}

extension SyntaxSnapshot {
    static let callableScopeKinds: Set<String> = ["function", "closure"]

    /// Callable scopes (functions and closures) strictly inside `owner`.
    func nestedCallableScopes(within owner: Range<Int>) -> [SourceScope] {
        scopes.filter {
            Self.callableScopeKinds.contains($0.kind) && $0.byteRange != owner
                && owner.lowerBound <= $0.byteRange.lowerBound && $0.byteRange.upperBound <= owner.upperBound
        }
    }

    /// Sites inside `owner` that no callable scope nested in `owner` contains.
    func directCallSites(within owner: Range<Int>) -> [CallSite] {
        let nested = nestedCallableScopes(within: owner)
        return callSites.filter { site in
            guard owner.lowerBound <= site.byteRange.lowerBound, site.byteRange.upperBound <= owner.upperBound else { return false }
            return !nested.contains { $0.byteRange.contains(site.anchorByte) }
        }
    }

    /// The closures and nested named functions directly inside `owner`
    /// (not those nested deeper), with the number of sites each owns.
    func conditionalCallables(within owner: Range<Int>) -> [ConditionalCallable] {
        let nested = nestedCallableScopes(within: owner)
        let outermost = nested.filter { candidate in
            !nested.contains { other in
                other.byteRange != candidate.byteRange
                    && other.byteRange.lowerBound <= candidate.byteRange.lowerBound
                    && candidate.byteRange.upperBound <= other.byteRange.upperBound
            }
        }
        return outermost.map { scope in
            let name = symbols.first { Self.callableKinds.contains($0.kind) && $0.byteRange == scope.byteRange }?.name
            return ConditionalCallable(kind: scope.kind == "closure" ? .closure : .function, name: name,
                                       byteRange: scope.byteRange, siteCount: directCallSites(within: scope.byteRange).count)
        }
    }

    /// The callable declaration whose name starts at `byte`, if any.
    func callableDeclaration(namedAt byte: Int) -> DocumentSymbol? {
        symbols.filter { Self.callableKinds.contains($0.kind) && $0.selectionByteRange.lowerBound == byte }
            .min { $0.byteRange.count < $1.byteRange.count }
    }

    /// Whether a callable declaration has a body fold (a declaration without
    /// one is abstract: a trait method, protocol requirement, or extern item).
    func hasBody(_ declaration: DocumentSymbol) -> Bool {
        folds.contains {
            $0.kind == "function" && $0.byteRange.lowerBound >= declaration.selectionByteRange.upperBound
                && $0.byteRange.upperBound <= declaration.byteRange.upperBound
        }
    }
}
