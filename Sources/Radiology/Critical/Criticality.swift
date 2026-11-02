import Foundation

/// Whether a symbol is a meaningful operation for skimming. `unknown` is
/// neutral: it is neither emphasized nor receded.
enum Criticality: String, Codable, Sendable, CaseIterable {
    case critical
    case ordinary
    case unknown

    var title: String {
        switch self {
        case .critical: "Critical"
        case .ordinary: "Non-Critical"
        case .unknown: "Unknown"
        }
    }
}

/// A classification with the deterministic evidence behind it, so menus and
/// tooltips can say why a symbol receded or stayed.
struct CriticalityClassification: Sendable, Equatable {
    enum Reason: String, Sendable {
        case symbolOverride
        case packageOverride
        case local
        case ffiPackage
        case ffiSignature
        case systemAPI
        case repositoryDefinition
        case runtimePlumbing
        case external

        var description: String {
            switch self {
            case .symbolOverride: "marked by you"
            case .packageOverride: "package marked by you"
            case .local: "local binding"
            case .ffiPackage: "FFI boundary"
            case .ffiSignature: "extern signature"
            case .systemAPI: "system API"
            case .repositoryDefinition: "defined in this repository"
            case .runtimePlumbing: "runtime plumbing"
            case .external: "external, no profile"
            }
        }
    }

    let criticality: Criticality
    let reason: Reason

    var isOverride: Bool { reason == .symbolOverride || reason == .packageOverride }
}
