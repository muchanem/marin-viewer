import Foundation

struct TraitImplementationGroup: Sendable, Equatable, Identifiable {
    let path: String
    let items: [TraitImplementation]
    var id: String { path }
}
