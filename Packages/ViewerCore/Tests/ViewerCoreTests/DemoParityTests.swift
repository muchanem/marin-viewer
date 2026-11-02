import Foundation
import Testing
@testable import ViewerCore

/// `Fixtures/pr10640/demo-render.json` is the output of the demo's own
/// `renderLines`, `diffVisible`, `rangeVisible` and `lineHTML` (run in Node
/// with blame on) over `expected.json`: per card, the segments, every gap's
/// label and button ranges, and the rows that carry a blame label. Each
/// card must come out the same from `DiffVisibility` and `Blame`, apart from
/// three deliberate differences that the tests below spell out:
///
/// 1. A gap that hides changed rows names them, "N added lines…" or "N lines…, M changed",
///    where the demo said "N unchanged lines…".
/// 2. An excerpt shows the deletions just before its first line. The demo's
///    `rangeVisible` showed those just after its last line only.
/// 3. Mark's resolved notes get the grey dot. In the demo, `.mk.has.mine`
///    comes after `.mk.has.resolved` in the CSS, so they stayed blue.
struct DemoParityTests {
    struct Case: Decodable {
        struct Segment: Decodable {
            var rows: [Int]?
            var label: String?
            var buttons: [Button]?
        }

        struct Button: Decodable {
            var title: String, lower: Int, upper: Int
            init(from decoder: any Decoder) throws {
                var container = try decoder.unkeyedContainer()
                title = try container.decode(String.self)
                lower = try container.decode(Int.self)
                upper = try container.decode(Int.self)
            }
        }

        var name: String
        var path: String
        var segments: [Segment]
        var labeled: [Int]
    }

    static func cases() throws -> [Case] {
        struct File: Decodable { var cases: [Case] }
        return try JSONDecoder().decode(File.self, from: Data(try Fixtures.text("pr10640/demo-render.json").utf8)).cases
    }

    @Test func everyDemoCardMatches() throws {
        let cases = try Self.cases()
        #expect(cases.count == 17)
        var differing: [String] = []
        for demo in cases {
            let rows = try Fixtures.expectedRows(demo.path)
            let shas = try Fixtures.expectedFile(demo.path)["blame"] as! [String]
            var visibility: DiffVisibility
            var wholeFile = false
            switch demo.name {
            case "diff": visibility = DiffVisibility(rows: rows)
            case "whole": visibility = DiffVisibility(rows: rows); wholeFile = true
            case "goto 327":
                visibility = DiffVisibility(rows: rows)
                #expect(visibility.goTo(newLine: 327, in: rows) != nil)
            default:
                let bounds = demo.name.dropFirst("excerpt ".count).split(separator: "-").map { Int($0)! }
                visibility = DiffVisibility(rows: rows, mode: .excerpt(bounds[0]...bounds[1]))
            }
            let segments = visibility.segments(wholeFile: wholeFile)
            let context = "\(demo.path) \(demo.name)"
            let extra = Self.visibleRows(segments).subtracting(Self.visibleRows(demo.segments))
            #expect(extra == Self.deletionsBeforeExcerpt(demo.name, rows: rows), "\(context)")
            if extra.isEmpty {
                #expect(segments.map(Self.render) == demo.segments.map { Self.render($0, rows: rows) }, "\(context)")
            } else {
                differing.append(context)
                #expect(Self.visibleRows(demo.segments).isSubset(of: Self.visibleRows(segments)), "\(context)")
            }
            let labeled = Blame(lineSHAs: shas, commits: [:]).labeledRows(rows, segments: segments)
            #expect(Array(labeled) == demo.labeled, "\(context)")
        }
        // Difference 2 changes none of the demo's eight excerpts: none of
        // them starts just below a deletion. `DiffVisibilityTests` covers it.
        #expect(differing.isEmpty, "\(differing)")
    }

    /// Difference 1: the demo's own labels, with gaps that hide changes
    /// relabelled; every other gap label must match the demo's verbatim.
    @Test func onlyGapsHidingChangesAreRelabelled() throws {
        var relabelled = 0
        for demo in try Self.cases() where demo.name.hasPrefix("excerpt ") {
            let rows = try Fixtures.expectedRows(demo.path)
            for segment in demo.segments {
                guard let label = segment.label, let buttons = segment.buttons, let all = buttons.last else { continue }
                let hidden = rows[all.lower..<all.upper]
                let changed = hidden.count(where: \.isChange)
                let ours = DiffGap(rows: all.lower..<all.upper, rowCount: rows.count, changedRows: changed,
                                   addedRows: hidden.count(where: { $0.kind == .added })).label
                if changed == 0 { #expect(ours == label) } else {
                    relabelled += 1
                    #expect(label.contains("unchanged") && !ours.contains("unchanged") && ours.hasPrefix("\(hidden.count) "))
                }
            }
        }
        #expect(relabelled > 0)
    }

    /// Difference 3, against the demo's CSS order.
    @Test func marksResolvedNotesAreGrey() {
        let note = ReviewNote(id: "f4", path: "x.py", line: 1, commit: "c", severity: .high, status: .resolved,
                              who: "you (agent draft)", l1: "", l2: "", created: "", updated: "")
        #expect(note.isMine)
        #expect(note.marker == .resolved)
    }

    static func visibleRows(_ segments: [DiffSegment]) -> IndexSet {
        var rows = IndexSet()
        for case .rows(let range) in segments { rows.insert(integersIn: range) }
        return rows
    }

    static func visibleRows(_ segments: [Case.Segment]) -> IndexSet {
        var rows = IndexSet()
        for segment in segments { if let range = segment.rows { rows.insert(integersIn: range[0]..<range[1]) } }
        return rows
    }

    /// The deleted rows directly above an excerpt's first line, which the
    /// demo hid and this port shows.
    static func deletionsBeforeExcerpt(_ name: String, rows: [DiffRow]) -> IndexSet {
        guard name.hasPrefix("excerpt ") else { return IndexSet() }
        let first = Int(name.dropFirst("excerpt ".count).split(separator: "-")[0])!
        guard let start = rows.firstIndex(where: { $0.newLine == first }) else { return IndexSet() }
        var lower = start
        while lower > 0, rows[lower - 1].kind == .deleted { lower -= 1 }
        return IndexSet(integersIn: lower..<start)
    }

    static func render(_ segment: DiffSegment) -> String {
        switch segment {
        case .rows(let rows): "rows \(rows.lowerBound) \(rows.upperBound)"
        case .gap(let gap): "gap \(gap.label) " + gap.expanders.map { "[\($0.title) \($0.rows.lowerBound) \($0.rows.upperBound)]" }.joined()
        }
    }

    /// The demo's segment, with difference 1 applied to its label.
    static func render(_ segment: Case.Segment, rows: [DiffRow]) -> String {
        if let range = segment.rows { return "rows \(range[0]) \(range[1])" }
        let buttons = segment.buttons ?? []
        var label = segment.label ?? ""
        if let all = buttons.last {
            let hidden = rows[all.lower..<all.upper]
            let changed = hidden.count(where: \.isChange)
            if changed > 0 {
                label = DiffGap(rows: all.lower..<all.upper, rowCount: rows.count, changedRows: changed,
                                addedRows: hidden.count(where: { $0.kind == .added })).label
            }
        }
        return "gap \(label) " + buttons.map { "[\($0.title) \($0.lower) \($0.upper)]" }.joined()
    }
}
