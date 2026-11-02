import Foundation

/// How Hide Tests presents one exact buffer: each test region keeps its
/// first line as a dimmed header and hides the rest through the fold
/// machinery. Byte ranges are canonical; TextKit conversion happens in the
/// viewer. Bound to path plus content identity, like `SourceProjection`.
struct TestCodePresentation: Equatable {
    struct Region: Equatable, Identifiable {
        /// The region's start byte, stable for one loaded document.
        let id: Int
        let byteRange: Range<Int>
        /// The visible first line's code inside the region.
        let headerByteRange: Range<Int>
        /// Everything after the header line's text; empty for a one-line region.
        let hiddenByteRange: Range<Int>
        let headerLine: Int
        let hiddenLineCount: Int
        let isHidden: Bool
    }

    let path: String
    let sourceIdentity: SourceContentIdentity
    let regions: [Region]

    var hiddenRegions: [Region] { regions.filter(\.isHidden) }

    init(regions: [TestRegion], revealed: Set<Int>, buffer: SourceBuffer, sourceIdentity: SourceContentIdentity) {
        path = buffer.path
        self.sourceIdentity = sourceIdentity
        self.regions = regions.compactMap { region in
            let range = region.byteRange
            guard !range.isEmpty, range.upperBound <= buffer.data.count else { return nil }
            let headerLine = buffer.line(atByte: range.lowerBound)
            let headerEnd = min(max(range.lowerBound, buffer.lineByteRange(headerLine).upperBound), range.upperBound)
            let lastLine = buffer.line(atByte: range.upperBound - 1)
            return Region(id: region.id, byteRange: range, headerByteRange: range.lowerBound..<headerEnd,
                          hiddenByteRange: headerEnd..<range.upperBound, headerLine: headerLine,
                          hiddenLineCount: max(0, lastLine - headerLine), isHidden: !revealed.contains(region.id))
        }
    }

    func matches(path: String, sourceIdentity: SourceContentIdentity?) -> Bool {
        self.path == path && self.sourceIdentity == sourceIdentity
    }

    /// Whether `byteRange` lies wholly inside a region that is currently hidden.
    func hides(_ byteRange: Range<Int>) -> Bool {
        hiddenRegions.contains { $0.byteRange.lowerBound <= byteRange.lowerBound && byteRange.upperBound <= $0.byteRange.upperBound }
    }
}
