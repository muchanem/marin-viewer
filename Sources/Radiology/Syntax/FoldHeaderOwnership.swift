import Foundation

/// Actual parser attachment of annotations/decorators to a named function.
/// Separate from lexical scopes, so call ownership/semantic coordinates do not change.
struct FoldHeaderOwnership: Equatable, Sendable {
    let declarationByteRange: Range<Int>
    let annotatedByteRange: Range<Int>
}
