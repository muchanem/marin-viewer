import Foundation

/// Classifies SCIP symbols by identity, package ownership, indexed metadata,
/// and the reader's overrides. Pure and deterministic; it never reads source
/// text or identifier spelling. See plans/critical-lens.md for the
/// precedence table this implements.
struct CriticalityPolicy: Sendable, Equatable {
    /// Package names that define at least one symbol in the index: the
    /// repository's own crates/modules, so cfg-inactive items of a repository
    /// crate still count as repository code.
    let repositoryPackages: Set<String>
    let overrides: CriticalityOverrides

    init(repositoryPackages: Set<String> = [], overrides: CriticalityOverrides = CriticalityOverrides()) {
        self.repositoryPackages = repositoryPackages
        self.overrides = overrides
    }

    static func repositoryPackages(in index: SemanticIndex) -> Set<String> {
        var packages = Set<String>()
        for id in index.definitions.keys where !id.isLocal {
            if let name = SCIPSymbolString.packageName(of: id.symbol) { packages.insert(name) }
        }
        return packages
    }

    func classify(_ id: SemanticSymbolID, in index: SemanticIndex) -> CriticalityClassification {
        classify(id, in: index, honoringOverrides: true)
    }

    /// The built-in result, for the "Built-In (…)" menu item.
    func builtInClassification(_ id: SemanticSymbolID, in index: SemanticIndex) -> CriticalityClassification {
        classify(id, in: index, honoringOverrides: false)
    }

    private func classify(_ id: SemanticSymbolID, in index: SemanticIndex, honoringOverrides: Bool) -> CriticalityClassification {
        if id.isLocal { return CriticalityClassification(criticality: .unknown, reason: .local) }
        let header = SCIPSymbolHeader(id.symbol)
        let package = header?.packageName
        if honoringOverrides {
            if let decision = overrides.symbolDecision(id.symbol) {
                return CriticalityClassification(criticality: decision, reason: .symbolOverride)
            }
            if let key = header?.packageKey, let decision = overrides.packageDecision(key) {
                return CriticalityClassification(criticality: decision, reason: .packageOverride)
            }
        }
        let descriptors = SCIPSymbolString.descriptorText(of: id.symbol)
        let profiled = header?.scheme == CriticalityProfiles.verifiedScheme
        if profiled, let package {
            if CriticalityProfiles.isFFIPackage(package) || CriticalityProfiles.isFFIDescriptor(package: package, descriptors: descriptors) {
                return CriticalityClassification(criticality: .critical, reason: .ffiPackage)
            }
        }
        if let signature = index.symbols[id]?.signature, signature.contains("extern \"") {
            return CriticalityClassification(criticality: .critical, reason: .ffiSignature)
        }
        if profiled, let package, CriticalityProfiles.isSystemAPI(package: package, descriptors: descriptors) {
            return CriticalityClassification(criticality: .critical, reason: .systemAPI)
        }
        if !index.definitions(of: id).isEmpty || package.map(repositoryPackages.contains) == true {
            return CriticalityClassification(criticality: .critical, reason: .repositoryDefinition)
        }
        if profiled, let package, CriticalityProfiles.runtimePackages.contains(package) {
            return CriticalityClassification(criticality: .ordinary, reason: .runtimePlumbing)
        }
        return CriticalityClassification(criticality: .unknown, reason: .external)
    }
}
