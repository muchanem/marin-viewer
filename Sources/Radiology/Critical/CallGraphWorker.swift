import Foundation

/// Off-main call-graph work: resolves parsed call sites to SCIP identities,
/// locates callee bodies (Tree-sitter declaration first, the indexer's
/// enclosing range as a fallback bound), and builds bounded frontiers. Every
/// cache is dropped when the repository, the index, or the policy changes;
/// per-file results also key on the exact bytes they were computed from.
actor CallGraphWorker {
    struct Configuration: Sendable, Equatable {
        let root: URL
        let index: SemanticIndex
        let indexRevision: Int
        let policy: CriticalityPolicy
        let policyRevision: Int

        static func == (lhs: Configuration, rhs: Configuration) -> Bool {
            lhs.root == rhs.root && lhs.indexRevision == rhs.indexRevision && lhs.policyRevision == rhs.policyRevision
                && lhs.index === rhs.index
        }
    }

    /// A file as loaded for graph work: bytes, structure, and occurrences.
    struct LoadedFile: Sendable {
        let buffer: SourceBuffer
        let syntax: SyntaxSnapshot?
        let semantics: DocumentSemantics?
        var identity: SourceContentIdentity { SourceContentIdentity(buffer.data) }
    }

    private struct FrontierKey: Hashable {
        let path: String
        let owner: Range<Int>
        let identity: SourceContentIdentity
    }

    private let sources = SourceStore()
    private let syntax = SyntaxWorker()
    private var configuration: Configuration?
    /// Bumped by every effective `configure` and by every effective byte
    /// invalidation in `prime`. An operation captures the epoch it started
    /// under and never writes a cache or continues a traversal after it
    /// changed, so data for an old index, root, policy, or old file bytes
    /// cannot repopulate the current caches, even from a load already in
    /// flight when the invalidation happened.
    private var epoch = 0
    /// Testing seam: delays file loads so reconfiguration during a load
    /// can be exercised deterministically.
    private let artificialLoadDelay: Duration
    private var files = BoundedCache<String, LoadedFile>(capacity: 48)
    private var summaries: [SemanticSymbolID: CallableSummary] = [:]
    private var frontiers: [FrontierKey: CriticalFrontier] = [:]
    private var classifications: [SemanticSymbolID: CriticalityClassification] = [:]
    private var builder = CriticalFrontierBuilder()
    /// Counts for tests: how many bodies were parsed and summaries built.
    private(set) var summaryBuildCount = 0
    private(set) var fileLoadCount = 0
    private(set) var frontierBuildCount = 0

    init(artificialLoadDelay: Duration = .zero) {
        self.artificialLoadDelay = artificialLoadDelay
    }

    /// Installs the inputs every result depends on. A change in any of them
    /// empties the caches, so a result for an old index, root, or policy can
    /// never be served again.
    func configure(_ configuration: Configuration) {
        guard configuration != self.configuration else { return }
        self.configuration = configuration
        epoch += 1
        files.removeAll()
        summaries.removeAll()
        frontiers.removeAll()
        classifications.removeAll()
    }

    func setLimits(maxDepth: Int, maxBodies: Int) {
        builder = CriticalFrontierBuilder(maxDepth: maxDepth, maxBodies: maxBodies)
    }

    /// Registers the open file's already-loaded bytes, structure, and
    /// occurrences, so summaries in it never re-read or re-parse it.
    func prime(buffer: SourceBuffer, syntax: SyntaxSnapshot?, semantics: DocumentSemantics?) {
        let file = LoadedFile(buffer: buffer, syntax: syntax?.path == buffer.path ? syntax : nil,
                              semantics: semantics?.path == buffer.path ? semantics : nil)
        if let cached = files[buffer.path] {
            if cached.identity == file.identity {
                // Same bytes: keep whatever structure and occurrences are already known.
                if (cached.syntax != nil || file.syntax == nil) && (cached.semantics != nil || file.semantics == nil) { return }
                files[buffer.path] = LoadedFile(buffer: cached.buffer, syntax: file.syntax ?? cached.syntax,
                                                semantics: file.semantics ?? cached.semantics)
                // Structure or occurrences arrived for bytes that previously
                // had none: "no body" answers for this file are no longer true.
                invalidate(path: buffer.path, includingNoBody: true)
                return
            }
            // Different bytes at this path: every summary built from the old
            // bytes is wrong, and so is every frontier that traversed one of
            // them, wherever its root lives.
            invalidate(path: buffer.path, includingNoBody: true)
        }
        files[buffer.path] = file
    }

    /// Drops summaries built from this file (and, when asked, no-body
    /// answers that may have come from it), every frontier (any root may
    /// have traversed it), and advances the epoch so an operation that
    /// already captured the old file can never store its result.
    private func invalidate(path: String, includingNoBody: Bool) {
        let index = configuration?.index
        summaries = summaries.filter { entry in
            if let body = entry.value.body { return body.path != path }
            guard includingNoBody else { return true }
            return index?.definitions(of: entry.key).first?.path != path
        }
        frontiers.removeAll()
        epoch += 1
    }

    // MARK: - Summaries

    /// Direct calls of the callable whose body is `owner` in the open file.
    func summary(in buffer: SourceBuffer, syntax: SyntaxSnapshot?, semantics: DocumentSemantics?,
                 owner: Range<Int>, callable: SemanticSymbolID?, hasBody: Bool) -> CallableSummary {
        prime(buffer: buffer, syntax: syntax, semantics: semantics)
        guard let file = files[buffer.path] else { return .noBody(.unreadable, callable: callable) }
        return summary(file: file, owner: owner, callable: callable, hasBody: hasBody)
    }

    /// Direct calls of a symbol, locating and reading its body as needed.
    /// A reconfiguration during the work yields an uncached no-body result
    /// that the caller's own generation guard discards.
    func summary(of symbol: SemanticSymbolID) async -> CallableSummary {
        await summary(of: symbol, epoch: epoch) ?? .noBody(.notIndexed, callable: symbol)
    }

    /// Nil when the worker was reconfigured under the operation.
    private func summary(of symbol: SemanticSymbolID, epoch: Int) async -> CallableSummary? {
        guard epoch == self.epoch, let configuration else { return nil }
        if let cached = summaries[symbol] { return cached }
        guard let built = await buildSummary(of: symbol, configuration: configuration, epoch: epoch),
              epoch == self.epoch else { return nil }
        summaries[symbol] = built
        return built
    }

    private func buildSummary(of symbol: SemanticSymbolID, configuration: Configuration, epoch: Int) async -> CallableSummary? {
        guard let position = configuration.index.definitions(of: symbol).first else {
            return .noBody(.external, callable: symbol)
        }
        guard let loaded = await load(path: position.path, configuration: configuration, epoch: epoch) else { return nil }
        guard let file = loaded else { return .noBody(.unreadable, callable: symbol) }
        guard SourceLanguageRegistry.language(for: position.path) != nil else {
            return .noBody(.unsupportedLanguage, callable: symbol)
        }
        guard let snapshot = file.syntax else { return .noBody(.noSyntax, callable: symbol) }
        guard file.semantics != nil else { return .noBody(.notIndexed, callable: symbol) }
        guard let range = file.buffer.byteRange(for: position.range, encoding: position.encoding) else {
            return .noBody(.notIndexed, callable: symbol)
        }
        if let declaration = snapshot.callableDeclaration(namedAt: range.lowerBound) {
            return summary(file: file, owner: declaration.byteRange, callable: symbol, hasBody: snapshot.hasBody(declaration),
                           configuration: configuration)
        }
        if let extent = configuration.index.definitionExtents[symbol], extent.path == position.path,
           let owner = file.buffer.byteRange(for: extent.range, encoding: extent.encoding), owner.count > range.count {
            return summary(file: file, owner: owner, callable: symbol, hasBody: true, configuration: configuration)
        }
        return .noBody(.abstract, callable: symbol)
    }

    private func summary(file: LoadedFile, owner: Range<Int>, callable: SemanticSymbolID?, hasBody: Bool) -> CallableSummary {
        guard let configuration else { return .noBody(.notIndexed, callable: callable) }
        return summary(file: file, owner: owner, callable: callable, hasBody: hasBody, configuration: configuration)
    }

    private func summary(file: LoadedFile, owner: Range<Int>, callable: SemanticSymbolID?, hasBody: Bool,
                         configuration: Configuration) -> CallableSummary {
        guard hasBody else { return .noBody(.abstract, callable: callable) }
        guard let snapshot = file.syntax else { return .noBody(.noSyntax, callable: callable) }
        guard snapshot.supportsCallSites else { return .noBody(.unsupportedLanguage, callable: callable) }
        guard let semantics = file.semantics else { return .noBody(.notIndexed, callable: callable) }
        summaryBuildCount += 1
        let body = CallableBody(path: file.buffer.path, byteRange: owner, sourceIdentity: file.identity)
        var gaps = CallCoverageGaps()
        gaps.parseErrors = snapshot.hasParseErrors
        var order: [SemanticSymbolID] = []
        var calls: [SemanticSymbolID: DirectCall] = [:]
        for site in snapshot.directCallSites(within: owner) {
            if site.isMacro { gaps.macroSites += 1 }
            guard let callee = Self.resolve(site, in: semantics) else {
                gaps.unresolvedSites += 1
                continue
            }
            if var existing = calls[callee] {
                existing = DirectCall(callee: callee, displayName: existing.displayName, kind: existing.kind,
                                      classification: existing.classification, firstSiteByte: existing.firstSiteByte,
                                      siteCount: existing.siteCount + 1, definition: existing.definition,
                                      isMacro: existing.isMacro || site.isMacro)
                calls[callee] = existing
                continue
            }
            let classification = classify(callee, in: configuration)
            calls[callee] = DirectCall(callee: callee, displayName: configuration.index.displayName(callee),
                                       kind: configuration.index.symbols[callee]?.kind ?? SemanticSymbolKind(rawValue: 0),
                                       classification: classification, firstSiteByte: site.anchorByte,
                                       siteCount: 1, definition: configuration.index.definitions(of: callee).first,
                                       isMacro: site.isMacro)
            order.append(callee)
        }
        let ordered = order.compactMap { calls[$0] }
        return CallableSummary(callable: callable, body: body, calls: ordered,
                               conditional: snapshot.conditionalCallables(within: owner),
                               coverage: gaps.isEmpty ? .complete : .partial(gaps))
    }

    /// The SCIP occurrence at a site's callee name: a single-line occurrence
    /// starting exactly at the name, the one matching the whole token first.
    static func resolve(_ site: CallSite, in semantics: DocumentSemantics) -> SemanticSymbolID? {
        guard let nameRange = site.nameByteRange else { return nil }
        let hits = semantics.occurrences(at: nameRange.lowerBound).filter {
            $0.range.startLine == $0.range.endLine && $0.byteRange.lowerBound == nameRange.lowerBound && !$0.byteRange.isEmpty
        }
        if let exact = hits.first(where: { $0.byteRange == nameRange }) { return exact.symbol }
        return hits.first?.symbol
    }

    private func classify(_ id: SemanticSymbolID, in configuration: Configuration) -> CriticalityClassification {
        if let cached = classifications[id] { return cached }
        let result = configuration.policy.classify(id, in: configuration.index)
        classifications[id] = result
        return result
    }

    // MARK: - Frontiers

    func frontier(in buffer: SourceBuffer, syntax: SyntaxSnapshot?, semantics: DocumentSemantics?,
                  owner: Range<Int>, callable: SemanticSymbolID?, hasBody: Bool) async -> CriticalFrontier {
        // Priming may invalidate (and advance the epoch); the root is built
        // synchronously from the primed file, so the epoch is captured after
        // both and this fresh request remains cacheable.
        let root = summary(in: buffer, syntax: syntax, semantics: semantics, owner: owner, callable: callable, hasBody: hasBody)
        let epoch = epoch
        let key = FrontierKey(path: buffer.path, owner: owner, identity: SourceContentIdentity(buffer.data))
        if let cached = frontiers[key] { return cached }
        if let callable { summaries[callable] = root }
        let frontier = await build(root: root, epoch: epoch)
        if epoch == self.epoch { frontiers[key] = frontier }
        return frontier
    }

    func frontier(of symbol: SemanticSymbolID) async -> CriticalFrontier {
        let epoch = epoch
        guard let root = await summary(of: symbol, epoch: epoch) else {
            return await build(root: .noBody(.notIndexed, callable: symbol), epoch: epoch)
        }
        guard let body = root.body else { return await build(root: root, epoch: epoch) }
        let key = FrontierKey(path: body.path, owner: body.byteRange, identity: body.sourceIdentity)
        if let cached = frontiers[key] { return cached }
        let frontier = await build(root: root, epoch: epoch)
        if epoch == self.epoch { frontiers[key] = frontier }
        return frontier
    }

    /// Traverses under one epoch: a body request after reconfiguration
    /// returns nil (a gap) and the result is never cached by the callers.
    private func build(root: CallableSummary, epoch: Int) async -> CriticalFrontier {
        frontierBuildCount += 1
        return await builder.build(root: root) { [self] callee in await summary(of: callee, epoch: epoch) }
    }

    // MARK: - Files

    /// Outer nil: reconfigured during the load (nothing cached). Inner nil:
    /// the file could not be read.
    private func load(path: String, configuration: Configuration, epoch: Int) async -> LoadedFile?? {
        if let cached = files[path] { return .some(cached) }
        if artificialLoadDelay > .zero { try? await Task.sleep(for: artificialLoadDelay) }
        guard let buffer = try? await sources.load(root: configuration.root, path: path) else {
            return epoch == self.epoch ? .some(nil) : nil
        }
        let snapshot = try? await syntax.parse(buffer)
        guard epoch == self.epoch else { return nil }
        // The viewer may have primed this path while the disk copy was
        // loading; the primed bytes are the ones on screen and win.
        if let primed = files[path] { return .some(primed) }
        fileLoadCount += 1
        let semantics = configuration.index.documents[path].map { DocumentSemantics.make(document: $0, buffer: buffer) }
        let file = LoadedFile(buffer: buffer, syntax: snapshot, semantics: semantics)
        files[path] = file
        return .some(file)
    }
}
