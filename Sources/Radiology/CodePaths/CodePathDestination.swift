import Foundation

struct CodePathDestination: Equatable, Sendable, Identifiable {
    let location: SourceLocation
    let line: Int
    var id: SourceLocation { location }
}
