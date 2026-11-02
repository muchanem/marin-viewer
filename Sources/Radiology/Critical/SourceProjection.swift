import Foundation

/// What a presentation mode asks the renderer to do with one exact buffer:
/// recede these canonical byte ranges. The renderer applies a projection
/// without knowing which mode produced it, and only to the bytes it was
/// computed for. Text, layout, and coordinates never change.
struct SourceProjection: Sendable, Equatable, Identifiable {
    let id: UUID
    let path: String
    let sourceIdentity: SourceContentIdentity
    /// Sorted and disjoint.
    let recededByteRanges: [Range<Int>]

    init(path: String, sourceIdentity: SourceContentIdentity, recededByteRanges: [Range<Int>]) {
        id = UUID()
        self.path = path
        self.sourceIdentity = sourceIdentity
        self.recededByteRanges = Self.normalized(recededByteRanges)
    }

    /// Exact-source contract: the same path and the same content identity
    /// (byte count and checksum). The viewer passes the identity it already
    /// holds, so no file is hashed on the hot path.
    func matches(path: String, sourceIdentity: SourceContentIdentity?) -> Bool {
        self.path == path && self.sourceIdentity == sourceIdentity
    }

    func matches(_ buffer: SourceBuffer) -> Bool {
        matches(path: buffer.path, sourceIdentity: SourceContentIdentity(buffer.data))
    }

    /// Sorts, drops empties, and merges touching or overlapping ranges.
    static func normalized(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var output: [Range<Int>] = []
        for range in ranges.filter({ !$0.isEmpty }).sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = output.last, range.lowerBound <= last.upperBound {
                output[output.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                output.append(range)
            }
        }
        return output
    }
}

/// Call-focused source: everything recedes except syntactic call-name tokens
/// that are critical or unknown. Syntax establishes a call, never an identity;
/// SCIP classification can only demote a resolved ordinary callee. The
/// complement remains canonical bytes, including punctuation and Unicode.
enum CriticalProjection {
    static func make(semantics: DocumentSemantics, buffer: SourceBuffer, syntax: SyntaxSnapshot?,
                     classify: (SemanticSymbolID) -> CriticalityClassification) -> SourceProjection {
        guard let syntax, syntax.path == buffer.path, syntax.supportsCallSites else {
            return SourceProjection(path: buffer.path, sourceIdentity: SourceContentIdentity(buffer.data), recededByteRanges: [])
        }
        var prominent: [Range<Int>] = []
        var memo: [SemanticSymbolID: Criticality] = [:]
        for site in syntax.callSites {
            guard let name = site.nameByteRange, !name.isEmpty,
                  name.lowerBound >= 0, name.upperBound <= buffer.data.count else { continue }
            if let symbol = CallGraphWorker.resolve(site, in: semantics) {
                let decision = memo[symbol] ?? classify(symbol).criticality
                memo[symbol] = decision
                if decision == .ordinary { continue }
            }
            prominent.append(name)
        }
        var receded: [Range<Int>] = []
        var cursor = 0
        for name in SourceProjection.normalized(prominent) {
            if cursor < name.lowerBound { receded.append(cursor..<name.lowerBound) }
            cursor = name.upperBound
        }
        if cursor < buffer.data.count { receded.append(cursor..<buffer.data.count) }
        return SourceProjection(path: buffer.path, sourceIdentity: SourceContentIdentity(buffer.data), recededByteRanges: receded)
    }
}
