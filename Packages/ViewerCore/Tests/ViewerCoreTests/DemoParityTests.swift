import Foundation
import Testing
@testable import ViewerCore

/// `Fixtures/pr10640/demo-render.json` is the output of the demo's own
/// `renderLines`, `diffVisible`, `rangeVisible` and `lineHTML` (run in Node
/// with blame on) over `expected.json`: per card, the segments, every gap's
/// label and button ranges, and the rows that carry a blame label. Each
/// card must come out the same from `DiffVisibility` and `Blame`.
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
            #expect(segments.map(Self.render) == demo.segments.map(Self.render), "\(context)")
            let labeled = Blame(lineSHAs: shas, commits: [:]).labeledRows(rows, segments: segments)
            #expect(Array(labeled) == demo.labeled, "\(context)")
        }
    }

    static func render(_ segment: DiffSegment) -> String {
        switch segment {
        case .rows(let rows): "rows \(rows.lowerBound) \(rows.upperBound)"
        case .gap(let gap): "gap \(gap.label) " + gap.expanders.map { "[\($0.title) \($0.rows.lowerBound) \($0.rows.upperBound)]" }.joined()
        }
    }

    static func render(_ segment: Case.Segment) -> String {
        if let rows = segment.rows { return "rows \(rows[0]) \(rows[1])" }
        return "gap \(segment.label ?? "") " + (segment.buttons ?? []).map { "[\($0.title) \($0.lower) \($0.upper)]" }.joined()
    }
}
