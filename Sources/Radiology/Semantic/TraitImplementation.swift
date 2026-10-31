import Foundation

/// A proven explicit source impl. Byte locations and signatures are tied to
/// the exact file bytes used during enrichment, and checked before activation.
struct TraitImplementation: Sendable, Equatable, Codable, Identifiable {
    let traitSymbol: String
    let path: String
    let byteRange: Range<Int>
    let traitNameRange: Range<Int>
    let line: Int
    let signature: String
    let targetType: String
    let isNegative: Bool
    let sourceBlob: String

    var id: String { "\(path):\(byteRange.lowerBound)" }
    var location: SourceLocation { SourceLocation(path: path, byteOffset: byteRange.lowerBound) }
}
