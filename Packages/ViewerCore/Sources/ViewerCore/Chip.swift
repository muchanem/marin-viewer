import Foundation

/// What a question is about: the context the app attaches to a session message when Mark asks
/// from a selection, a file, a step, a diagram box or a review note. It encodes to the sidecar's
/// `Chip` schema in `sidecar/src/protocol.ts`, so the two must change together.
public struct Chip: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case selection, symbol, line, file, step, box, note
    }

    public var kind: Kind
    public var path: String?
    /// First and last line on the head side, inclusive.
    public var lines: ClosedRange<Int>?
    public var symbol: String?
    public var commit: String
    /// The text shown on the chip, such as "http_service.py:125-147 · _pump".
    public var label: String

    public init(
        kind: Kind, path: String? = nil, lines: ClosedRange<Int>? = nil, symbol: String? = nil,
        commit: String, label: String
    ) {
        self.kind = kind
        self.path = path
        self.lines = lines
        self.symbol = symbol
        self.commit = commit
        self.label = label
    }

    private enum CodingKeys: String, CodingKey {
        case kind, path, lines, symbol, commit, label
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        path = try c.decodeIfPresent(String.self, forKey: .path)
        if let pair = try c.decodeIfPresent([Int].self, forKey: .lines) {
            guard pair.count == 2, pair[0] <= pair[1] else {
                throw DecodingError.dataCorruptedError(
                    forKey: .lines, in: c, debugDescription: "lines must be [first, last]")
            }
            lines = pair[0]...pair[1]
        }
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
        commit = try c.decode(String.self, forKey: .commit)
        label = try c.decode(String.self, forKey: .label)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(path, forKey: .path)
        try c.encodeIfPresent(lines.map { [$0.lowerBound, $0.upperBound] }, forKey: .lines)
        try c.encodeIfPresent(symbol, forKey: .symbol)
        try c.encode(commit, forKey: .commit)
        try c.encode(label, forKey: .label)
    }
}
