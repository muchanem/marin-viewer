import Foundation

/// Prepared off the reader's current (commit-time) bytes; never a click-time session clone.
struct PRRefreshRestoration {
    let buffer: SourceBuffer?
    let caret: SourceLocation?
    let viewportByte: Int?
    let pins: OccurrencePinStore
    let notice: String?
}
