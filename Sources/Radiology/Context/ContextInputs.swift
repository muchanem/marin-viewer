import Foundation

/// Everything the Context inspector derives its state from, captured on the
/// main actor at one instant. Copying it is cheap: the buffer, syntax, and
/// document maps are copy-on-write values and the index is an immutable class.
struct ContextInputs {
    let root: URL?
    let buffer: SourceBuffer?
    let sourceIdentity: SourceContentIdentity?
    let syntax: SyntaxSnapshot?
    let caretByte: Int?
    let index: SemanticIndex
    let indexRevision: Int
    let documentSemantics: DocumentSemantics?
    let documentRevision: Int
}
