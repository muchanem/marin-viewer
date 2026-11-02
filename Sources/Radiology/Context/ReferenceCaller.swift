import Foundation

/// A callable owning a reference or call site. Locations point at the site,
/// so following a branch opens the actual call, with ordinary Back behavior.
struct ReferenceCaller: Sendable, Equatable, Identifiable {
    let id: Int
    let depth: Int
    let symbol: SemanticSymbolID?
    let name: String
    let location: SourceLocation
    let line: Int
    let note: String?
}
