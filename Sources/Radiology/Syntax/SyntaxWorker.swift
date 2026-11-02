import Foundation
import SwiftTreeSitter
import TreeSitter

/// Parses source off the main actor and returns Sendable, byte-addressed
/// structure. Parsers, trees, and compiled queries never leave this actor.
actor SyntaxWorker {
    private var querySets: [String: SyntaxQuerySet] = [:]

    func parse(_ buffer: SourceBuffer) throws -> SyntaxSnapshot? {
        guard let language = SourceLanguageRegistry.language(for: buffer.path) else { return nil }
        try Task.checkCancellation()

        let queries = try queries(for: language)
        let parser = Parser()
        try parser.setLanguage(language.treeSitterLanguage)
        let data = buffer.data
        let previousTree: Tree? = nil
        guard let mutableTree = parser.parse(tree: previousTree, encoding: TSInputEncodingUTF8, readBlock: { offset, _ in
            guard offset < data.count else { return nil }
            return data.subdata(in: offset..<min(data.count, offset + 32_768))
        }), let tree = mutableTree.copy(), let root = tree.rootNode else {
            throw BrowserError.message("Tree-sitter could not parse this \(language.displayName) file.")
        }
        try Task.checkCancellation()
        let tests = TestRegionDetector.supportedLanguageIDs.contains(language.id)
            ? TestRegionDetector(languageID: language.id, buffer: buffer).detect(root: root)
            : TestRegionDetector.Result()
        try Task.checkCancellation()

        return SyntaxSnapshot(
            path: buffer.path,
            languageID: language.id,
            languageName: language.displayName,
            highlights: try highlights(queries.highlights, tree: tree, data: data),
            folds: try folds(queries.folds, tree: tree, buffer: buffer),
            symbols: try symbols(queries.symbols, tree: tree, data: data, languageID: language.id),
            scopes: try scopes(queries.scopes, tree: tree, data: data),
            hasParseErrors: root.hasError,
            callSites: try callSites(queries.calls, tree: tree, data: data),
            supportsCallSites: queries.calls != nil,
            testRegions: tests.regions,
            isTestOnlyDocument: tests.isTestOnlyDocument,
            foldHeaderOwnership: foldHeaders(root: root, languageID: language.id),
            rustTraitImpls: language.id == "rust" ? try RustTraitImplSyntax.extract(root: root, data: data) : [],
            recoveredFunctionDeclarations: root.hasError && ["c", "cpp"].contains(language.id)
                ? try recoverFunctionDeclarations(root: root, data: data) : [])
    }

    /// A lightweight indexing pass: no highlighting, folds, calls, or outline.
    func rustTraitImpls(_ buffer: SourceBuffer) throws -> (impls: [RustTraitImplSyntax], hasErrors: Bool) {
        guard let language = SourceLanguageRegistry.language(for: buffer.path), language.id == "rust" else { return ([], false) }
        try Task.checkCancellation()
        let parser = Parser()
        try parser.setLanguage(language.treeSitterLanguage)
        let data = buffer.data
        let previousTree: Tree? = nil
        guard let tree = parser.parse(tree: previousTree, encoding: TSInputEncodingUTF8, readBlock: { offset, _ in
            guard offset < data.count else { return nil }
            return data.subdata(in: offset..<min(data.count, offset + 32_768))
        })?.copy(), let root = tree.rootNode else { throw BrowserError.message("Rust structure could not be read.") }
        return (try RustTraitImplSyntax.extract(root: root, data: data), root.hasError)
    }

    /// `@call.name` plus the `@call`/`@call.<kind>` capture of each match,
    /// in source order. `@call.any` is the fallback over every call node: a
    /// site it alone matches has no supported callee name and is kept as a
    /// `dynamic` site, so coverage counts it instead of dropping it.
    /// Comments and string literals are leaves to the parser, so nothing
    /// inside them can match.
    private func callSites(_ query: Query?, tree: Tree, data: Data) throws -> [CallSite] {
        guard let query else { return [] }
        var named: [Range<Int>: CallSite] = [:]
        var fallback: [Range<Int>] = []
        for match in try matches(query, tree: tree, data: data) {
            guard let site = match.captures.first(where: { capture in
                guard let captureName = capture.name else { return false }
                return captureName == "call" || (captureName.hasPrefix("call.") && captureName != "call.name")
            }) else { continue }
            let siteRange = intRange(site.node.byteRange)
            guard siteRange.upperBound <= data.count else { continue }
            if site.name == "call.any" {
                fallback.append(siteRange)
                continue
            }
            guard let name = match.captures.first(where: { $0.name == "call.name" }) else { continue }
            let kind = site.name == "call" ? "call" : String(site.name?.dropFirst("call.".count) ?? "call")
            let nameRange = intRange(name.node.byteRange)
            guard nameRange.upperBound <= data.count, !nameRange.isEmpty, named[siteRange] == nil else { continue }
            named[siteRange] = CallSite(kind: kind, nameByteRange: nameRange, byteRange: siteRange)
        }
        var sites = Array(named.values)
        var seen = Set(named.keys)
        for range in fallback where seen.insert(range).inserted {
            sites.append(CallSite(kind: "dynamic", nameByteRange: nil, byteRange: range))
        }
        return sites.sorted { ($0.anchorByte, $0.byteRange.lowerBound) < ($1.anchorByte, $1.byteRange.lowerBound) }
    }

    /// Query compilation is expensive, so each grammar is compiled once per session.
    private func queries(for language: SourceLanguage) throws -> SyntaxQuerySet {
        if let cached = querySets[language.id] { return cached }
        let compiled = try SyntaxQueryLoader.compile(language)
        querySets[language.id] = compiled
        return compiled
    }

    // MARK: - Roles

    private func highlights(_ query: Query?, tree: Tree, data: Data) throws -> [SyntaxHighlight] {
        guard let query else { return [] }
        var captured: [(name: String, range: Range<Int>, pattern: Int)] = []
        for match in try matches(query, tree: tree, data: data) {
            for capture in match.captures {
                guard let name = capture.name, !name.hasPrefix("_") else { continue }
                captured.append((name, intRange(capture.node.byteRange), match.patternIndex))
            }
        }
        // Painting order: widest span first at a given start, then query order,
        // so a nested or later pattern colours over a broader earlier one.
        captured.sort { lhs, rhs in
            if lhs.range.lowerBound != rhs.range.lowerBound { return lhs.range.lowerBound < rhs.range.lowerBound }
            if lhs.range.count != rhs.range.count { return lhs.range.count > rhs.range.count }
            return lhs.pattern < rhs.pattern
        }
        return captured.map { SyntaxHighlight(name: $0.name, byteRange: $0.range) }
    }

    private func folds(_ query: Query?, tree: Tree, buffer: SourceBuffer) throws -> [SourceFold] {
        guard let query else { return [] }
        var best: [Range<Int>: String] = [:]
        for match in try matches(query, tree: tree, data: buffer.data) {
            for capture in match.captures {
                guard let name = capture.name, name.hasPrefix("fold.") else { continue }
                let range = intRange(capture.node.byteRange)
                // Only a span that covers more than one line can be collapsed.
                guard buffer.line(atByte: range.lowerBound)
                        < buffer.line(atByte: max(range.lowerBound, range.upperBound - 1)) else { continue }
                let kind = String(name.dropFirst("fold.".count))
                if let existing = best[range], Self.foldRank(existing) <= Self.foldRank(kind) { continue }
                best[range] = kind
            }
        }
        return best.map { SourceFold(kind: $0.value, byteRange: $0.key) }
            .sorted { lhs, rhs in
                lhs.byteRange.lowerBound == rhs.byteRange.lowerBound
                    ? lhs.byteRange.upperBound > rhs.byteRange.upperBound
                    : lhs.byteRange.lowerBound < rhs.byteRange.lowerBound
            }
    }

    private func scopes(_ query: Query?, tree: Tree, data: Data) throws -> [SourceScope] {
        guard let query else { return [] }
        var output: [SourceScope] = []
        for match in try matches(query, tree: tree, data: data) {
            for capture in match.captures where capture.name?.hasPrefix("scope.") == true {
                guard let name = capture.name else { continue }
                output.append(SourceScope(kind: String(name.dropFirst("scope.".count)),
                                          byteRange: intRange(capture.node.byteRange)))
            }
        }
        return output.sorted { lhs, rhs in
            lhs.byteRange.lowerBound == rhs.byteRange.lowerBound
                ? lhs.byteRange.upperBound > rhs.byteRange.upperBound
                : lhs.byteRange.lowerBound < rhs.byteRange.lowerBound
        }
    }

    private func symbols(_ query: Query?, tree: Tree, data: Data, languageID: String) throws -> [DocumentSymbol] {
        guard let query else { return [] }
        var found: [(kind: String, range: Range<Int>, name: Range<Int>, text: String)] = []
        for match in try matches(query, tree: tree, data: data) {
            guard let symbol = match.captures.first(where: { $0.name?.hasPrefix("symbol.") == true }),
                  let captureName = symbol.name,
                  let nameCapture = match.captures.first(where: { $0.name == "name" }) else { continue }
            let range = intRange(symbol.node.byteRange)
            let nameNode: Node
            if languageID == "c" || languageID == "cpp" {
                let isPrototype = symbol.node.nodeType == "declaration" || symbol.node.nodeType == "field_declaration"
                guard let resolved = CDeclarationSyntax.name(in: nameCapture.node, requireFunction: isPrototype,
                                                            allowFunctionPointer: captureName == "symbol.typealias") else { continue }
                nameNode = resolved
            } else {
                nameNode = nameCapture.node
            }
            let nameRange = intRange(nameNode.byteRange)
            guard nameRange.upperBound <= data.count, !nameRange.isEmpty else { continue }
            found.append((String(captureName.dropFirst("symbol.".count)), range, nameRange,
                          String(decoding: data[nameRange], as: UTF8.self)))
        }
        // One row per declaration: when several patterns describe the same node,
        // keep the most specific kind.
        var byRange: [Range<Int>: (kind: String, name: Range<Int>, text: String)] = [:]
        for item in found {
            if let existing = byRange[item.range],
               Self.symbolRank(existing.kind) <= Self.symbolRank(item.kind) { continue }
            byRange[item.range] = (item.kind, item.name, item.text)
        }
        let ordered: [(range: Range<Int>, kind: String, name: Range<Int>, text: String)] = byRange
            .map { (range: $0.key, kind: $0.value.kind, name: $0.value.name, text: $0.value.text) }
            .sorted { lhs, rhs in
                if lhs.range.lowerBound != rhs.range.lowerBound { return lhs.range.lowerBound < rhs.range.lowerBound }
                return lhs.range.upperBound > rhs.range.upperBound
            }
        var enclosing: [Range<Int>] = []
        var output: [DocumentSymbol] = []
        for entry in ordered {
            while let last = enclosing.last,
                  !(last.lowerBound <= entry.range.lowerBound && entry.range.upperBound <= last.upperBound) {
                enclosing.removeLast()
            }
            output.append(DocumentSymbol(name: entry.text, kind: entry.kind, byteRange: entry.range,
                                         selectionByteRange: entry.name, depth: enclosing.count))
            enclosing.append(entry.range)
        }
        return output
    }

    // MARK: - Query execution

    /// Runs a query and drops matches whose predicates fail.
    ///
    /// `QueryMatch.allowed(in:)` cannot be used here: it resolves predicate text
    /// through `Node.range`, which SwiftTreeSitter derives assuming UTF-16 input.
    /// Radiology parses UTF-8, so predicates are evaluated against the canonical
    /// byte ranges instead.
    private func matches(_ query: Query, tree: Tree, data: Data) throws -> [QueryMatch] {
        let cursor = query.execute(in: tree)
        var output: [QueryMatch] = []
        while let match = cursor.next() {
            try Task.checkCancellation()
            if predicatesAllow(match, data: data) { output.append(match) }
        }
        return output
    }

    private func predicatesAllow(_ match: QueryMatch, data: Data) -> Bool {
        for predicate in match.predicates {
            switch predicate {
            case .set, .generic, .isNot:
                // `#set!` is metadata; `#is-not? local` needs name resolution
                // Radiology does not have. Neither filters a match.
                continue
            default:
                for capture in predicate.captures(in: match) {
                    let range = intRange(capture.node.byteRange)
                    guard range.upperBound <= data.count else { return false }
                    guard predicate.evalulate(with: String(decoding: data[range], as: UTF8.self)) else { return false }
                }
            }
        }
        return true
    }

    private func intRange(_ range: Range<UInt32>) -> Range<Int> { Int(range.lowerBound)..<Int(range.upperBound) }

    /// Lower rank wins when two fold patterns capture the same node.
    private static func foldRank(_ kind: String) -> Int {
        switch kind {
        case "function": 0
        case "type": 1
        case "comment": 2
        case "imports": 3
        default: 4
        }
    }

    /// Lower rank wins when two symbol patterns capture the same declaration.
    private static func symbolRank(_ kind: String) -> Int {
        switch kind {
        case "type", "protocol", "enum", "struct": 0
        case "function", "method", "initializer", "deinitializer": 1
        case "extension", "module", "typealias", "macro": 2
        case "property", "constant", "case": 3
        default: 4
        }
    }
}
