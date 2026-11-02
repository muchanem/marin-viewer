import Foundation

/// A stable identity for one immutable source buffer. Pins are session state,
/// but must not survive changed bytes at the same repository-relative path.
struct SourceContentIdentity: Hashable, Sendable {
    let byteCount: Int
    let checksum: UInt64

    init(_ data: Data) {
        byteCount = data.count
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        checksum = hash
    }
}

enum OccurrenceGroupIdentity: Hashable, Sendable {
    case semantic(SemanticSymbolID)
    case syntactic(scope: Range<Int>, spelling: Data)
}

struct OccurrenceGroup: Equatable, Sendable {
    let identity: OccurrenceGroupIdentity
    let activeByteRange: Range<Int>
    let byteRanges: [Range<Int>]
}

struct PinnedOccurrenceGroup: Equatable, Sendable, Identifiable {
    let identity: OccurrenceGroupIdentity
    let byteRanges: [Range<Int>]
    let colorSlot: Int
    var id: OccurrenceGroupIdentity { identity }
}

/// Repository-session pin storage. Color slots only advance, so removing one
/// pin never recolors the groups that remain and the palette may cycle freely.
struct OccurrencePinStore: Equatable, Sendable {
    private struct Document: Equatable, Sendable {
        let sourceIdentity: SourceContentIdentity
        var groups: [PinnedOccurrenceGroup]
    }

    private var documents: [String: Document] = [:]
    private var nextColorSlot = 0

    mutating func reconcile(path: String, sourceIdentity: SourceContentIdentity) {
        guard let document = documents[path], document.sourceIdentity != sourceIdentity else { return }
        documents.removeValue(forKey: path)
    }

    func groups(path: String, sourceIdentity: SourceContentIdentity) -> [PinnedOccurrenceGroup] {
        guard let document = documents[path], document.sourceIdentity == sourceIdentity else { return [] }
        return document.groups
    }

    func retainingDocument(from oldKey: String, to newKey: String, identity: SourceContentIdentity) -> Self {
        var result = Self()
        if let document = documents[oldKey], document.sourceIdentity == identity {
            result.documents[newKey] = document
            result.nextColorSlot = nextColorSlot
        }
        return result
    }

    /// Returns true when pinned and false when an existing group was removed.
    @discardableResult
    mutating func toggle(_ group: OccurrenceGroup, path: String,
                         sourceIdentity: SourceContentIdentity, clickedByte: Int) -> Bool {
        reconcile(path: path, sourceIdentity: sourceIdentity)
        var document = documents[path] ?? Document(sourceIdentity: sourceIdentity, groups: [])
        // Identity is authoritative. Range containment additionally reconciles
        // a cfg-inactive fallback that later gains a complete SCIP identity.
        if let index = document.groups.firstIndex(where: {
            $0.identity == group.identity
                || ($0.byteRanges.contains(where: { $0.contains(clickedByte) })
                    && Set($0.byteRanges) == Set(group.byteRanges))
        }) {
            document.groups.remove(at: index)
            if document.groups.isEmpty { documents.removeValue(forKey: path) }
            else { documents[path] = document }
            return false
        }
        document.groups.append(PinnedOccurrenceGroup(identity: group.identity,
                                                     byteRanges: group.byteRanges,
                                                     colorSlot: nextColorSlot))
        nextColorSlot += 1
        documents[path] = document
        return true
    }
}

