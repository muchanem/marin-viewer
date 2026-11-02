import Foundation

/// How the source surface presents the file. Normal shows the file as it is.
/// Other modes are projections layered over the same text: nothing is
/// rewritten or reflowed, and every coordinate stays canonical. The base
/// source model and renderer know only `SourceProjection`, never a mode.
enum SourceMode: String, CaseIterable, Identifiable, Sendable {
    case normal
    case critical

    var id: Self { self }

    var title: String {
        switch self {
        case .normal: "Normal"
        case .critical: "Critical"
        }
    }

    var help: String {
        switch self {
        case .normal: "Show the source as written."
        case .critical: "Recede runtime plumbing so repository, system, and FFI operations stand out."
        }
    }
}
