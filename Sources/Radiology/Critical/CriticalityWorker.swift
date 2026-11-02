import Foundation

/// Off-main classification and projection with caches keyed by the index
/// revision, the policy revision, and the exact bytes of the document.
/// Anything older is dropped, so a stale classification never survives an
/// index replacement or an override change.
actor CriticalityWorker {
    private struct PolicyKey: Equatable {
        let indexRevision: Int
        let policyRevision: Int
    }

    private struct ProjectionKey: Hashable {
        let path: String
        let sourceIdentity: SourceContentIdentity
        let documentRevision: Int
        let indexRevision: Int
        let policyRevision: Int
        let hasSyntax: Bool
    }

    private var policyKey: PolicyKey?
    private var policy = CriticalityPolicy()
    private var classifications: [SemanticSymbolID: CriticalityClassification] = [:]
    private var packagesIndexRevision = -1
    private var repositoryPackages: Set<String> = []
    private var projections = BoundedCache<ProjectionKey, SourceProjection>(capacity: 8)
    /// How many projections were actually built, so tests can prove reuse.
    private(set) var projectionBuildCount = 0

    /// Package names defining symbols in this index, computed once per index.
    func repositoryPackages(in index: SemanticIndex, indexRevision: Int) -> Set<String> {
        if packagesIndexRevision != indexRevision {
            repositoryPackages = CriticalityPolicy.repositoryPackages(in: index)
            packagesIndexRevision = indexRevision
        }
        return repositoryPackages
    }

    func classification(of id: SemanticSymbolID, index: SemanticIndex, indexRevision: Int,
                        overrides: CriticalityOverrides, policyRevision: Int) -> CriticalityClassification {
        preparePolicy(index: index, indexRevision: indexRevision, overrides: overrides, policyRevision: policyRevision)
        if let cached = classifications[id] { return cached }
        let result = policy.classify(id, in: index)
        classifications[id] = result
        return result
    }

    func projection(semantics: DocumentSemantics, buffer: SourceBuffer, syntax: SyntaxSnapshot?, index: SemanticIndex,
                    indexRevision: Int, documentRevision: Int, overrides: CriticalityOverrides, policyRevision: Int) -> SourceProjection {
        // Structure is a pure function of the bytes, so its presence is
        // enough to key on; a snapshot comparison would cost more than a rebuild.
        let key = ProjectionKey(path: buffer.path, sourceIdentity: SourceContentIdentity(buffer.data),
                                documentRevision: documentRevision, indexRevision: indexRevision, policyRevision: policyRevision,
                                hasSyntax: syntax?.path == buffer.path)
        if let cached = projections[key] { return cached }
        preparePolicy(index: index, indexRevision: indexRevision, overrides: overrides, policyRevision: policyRevision)
        projectionBuildCount += 1
        let projection = CriticalProjection.make(semantics: semantics, buffer: buffer, syntax: syntax) { id in
            if let cached = classifications[id] { return cached }
            let result = policy.classify(id, in: index)
            classifications[id] = result
            return result
        }
        projections[key] = projection
        return projection
    }

    private func preparePolicy(index: SemanticIndex, indexRevision: Int, overrides: CriticalityOverrides, policyRevision: Int) {
        let key = PolicyKey(indexRevision: indexRevision, policyRevision: policyRevision)
        guard key != policyKey else { return }
        policyKey = key
        classifications.removeAll(keepingCapacity: true)
        policy = CriticalityPolicy(repositoryPackages: repositoryPackages(in: index, indexRevision: indexRevision), overrides: overrides)
    }
}
