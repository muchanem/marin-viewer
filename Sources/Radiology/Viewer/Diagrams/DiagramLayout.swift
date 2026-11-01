import AppKit
import ViewerCore

/// The sidecar's `layout` result (`LayoutResult` in `sidecar/src/layout.ts`). Every coordinate is
/// in card space: the card is 460×196 unless `overflow`, when the extent is the natural size at
/// `minScale`.
struct DiagramLayoutResult: Codable, Hashable, Sendable {
    struct Box: Codable, Hashable, Sendable {
        var x: Double
        var y: Double
        var w: Double
        var h: Double
        var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    }

    struct Size: Codable, Hashable, Sendable {
        var width: Double
        var height: Double
    }

    struct Node: Codable, Hashable, Sendable, Identifiable {
        var id: String
        var label: String
        var sub: String?
        var step: Int?
        var at: CodeLocation?
        var paths: [String]?
        var group: Int?
        var x: Double
        var y: Double
        var w: Double
        var h: Double
        var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    }

    struct Group: Codable, Hashable, Sendable {
        var label: String
        var members: [String]
        var x: Double
        var y: Double
        var w: Double
        var h: Double
        var labelBox: Box
        var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }

        enum CodingKeys: String, CodingKey {
            case label, members, x, y, w, h
            case labelBox = "label_box"
        }
    }

    struct Edge: Codable, Hashable, Sendable {
        var from: String
        var to: String
        var label: String?
        var points: [[Double]]
        var labelBox: Box?

        enum CodingKeys: String, CodingKey {
            case from, to, label, points
            case labelBox = "label_box"
        }

        var cgPoints: [CGPoint] { points.compactMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil } }
    }

    var title: String?
    var mode: String
    var width: Double
    var height: Double
    var scale: Double
    var minScale: Double
    var overflow: Bool
    var natural: Size
    var nodes: [Node]
    var groups: [Group]
    var edges: [Edge]
    var warnings: [String]

    func node(id: String) -> Node? { nodes.first { $0.id == id } }
}

/// Which diagram a layout belongs to.
enum DiagramKey: Hashable, Sendable, Identifiable, CustomStringConvertible {
    var id: Self { self }
    /// The subsystem's "In Marin" map.
    case system
    /// The PR map, "Inside this PR".
    case pr
    case step(Int)

    var description: String {
        switch self {
        case .system: "In Marin"
        case .pr: "PR map"
        case .step(let id): "step \(id)"
        }
    }
}

enum DiagramLayoutPhase: Equatable, Sendable {
    case loading
    case ready(DiagramLayoutResult)
    case failed(String)

    var result: DiagramLayoutResult? { if case .ready(let result) = self { result } else { nil } }
}

/// The demo's diagram type, measured with the app's own fonts so the sidecar sizes boxes from
/// real text widths (`sizes` in the `layout` request). Sizes are at scale 1, in card points.
enum DiagramMetrics {
    static let card = CGSize(width: 460, height: 196)
    static let labelSize: CGFloat = 10.5
    static let subSize: CGFloat = 9
    static let codeLabelSize: CGFloat = 9.5
    static let edgeLabelSize: CGFloat = 8.5
    static let groupLabelSize: CGFloat = 9
    /// Text insets 8 points on each side, as in the demo.
    static let horizontalPadding: CGFloat = 16
    static let minWidth: CGFloat = 56
    static let maxWidth: CGFloat = 240

    static func labelFont(code: Bool, scale: CGFloat = 1) -> NSFont {
        code ? .monospacedSystemFont(ofSize: codeLabelSize * scale, weight: .regular)
            : .systemFont(ofSize: labelSize * scale)
    }
    static func subFont(scale: CGFloat = 1) -> NSFont { .systemFont(ofSize: subSize * scale) }
    static func edgeFont(scale: CGFloat = 1) -> NSFont { .systemFont(ofSize: edgeLabelSize * scale) }
    static func groupFont(scale: CGFloat = 1) -> NSFont { .systemFont(ofSize: groupLabelSize * scale) }

    static func width(of text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// The box size `layout.ts` would estimate, from real glyph widths: the wider of label and
    /// sub-label plus padding, clamped to 56…240, 34 high with a sub-label and 26 without.
    static func size(of node: DiagramNode, code: Bool) -> CGSize {
        let label = width(of: node.label, font: labelFont(code: code))
        let sub = node.sub.isEmpty ? 0 : width(of: node.sub, font: subFont())
        let w = min(maxWidth, max(minWidth, max(label, sub) + horizontalPadding))
        return CGSize(width: w.rounded(), height: node.sub.isEmpty ? 26 : 34)
    }

    /// Step diagrams draw boxes that open code in monospace, as the demo does.
    static func isCode(_ node: DiagramNode, in key: DiagramKey) -> Bool {
        if case .step = key { return node.at != nil }
        return false
    }

    /// The `sizes` field of a `layout` request.
    static func sizes(for diagram: Diagram, key: DiagramKey) -> JSONValue {
        .object(Dictionary(uniqueKeysWithValues: diagram.nodes.map { node in
            let size = size(of: node, code: isCode(node, in: key))
            return (node.id, JSONValue.object(["w": .number(size.width), "h": .number(size.height)]))
        }))
    }
}
