import Foundation
import Testing
@testable import ViewerCore

/// Cases worked by hand from `diffVisible`, `rangeVisible` and
/// `renderLines` in `demo/index.html`.
struct DiffVisibilityTests {
    /// 40 context rows, a one-line change at rows 40-41, 58 more context rows.
    static let oneChange = Fixtures.rows(String(repeating: "c", count: 40) + "da" + String(repeating: "c", count: 58))

    @Test func changedRowsKeepThreeRowsOfContext() {
        let visibility = DiffVisibility(rows: Self.oneChange)
        #expect(visibility.base == IndexSet(integersIn: 37...44))
        let segments = visibility.segments()
        #expect(segments.count == 3)
        guard case .gap(let top) = segments[0], case .rows(let shown) = segments[1], case .gap(let end) = segments[2] else {
            Issue.record("expected gap, rows, gap: \(segments)")
            return
        }
        #expect(shown == 37..<45)

        #expect(top.rows == 0..<37 && top.isAtTop && !top.isAtEnd)
        #expect(top.label == "37 unchanged lines at the top")
        // At the top there is nothing above to extend downward from.
        #expect(top.expanders.map(\.title) == ["Show 15 above", "Show all"])
        #expect(top.expanders.map(\.rows) == [22..<37, 0..<37])

        #expect(end.rows == 45..<100 && end.isAtEnd && !end.isAtTop)
        #expect(end.label == "55 unchanged lines to the end")
        #expect(end.expanders.map(\.title) == ["Show 15 below", "Show all"])
        #expect(end.expanders.map(\.rows) == [45..<60, 45..<100])
    }

    @Test func middleGapsOfMoreThanThirtyOfferBothSteps() {
        // Changes at rows 5 and 50: rows 2...8 and 47...53 are shown.
        let rows = Fixtures.rows(String(repeating: "c", count: 5) + "a" + String(repeating: "c", count: 44) + "a" + String(repeating: "c", count: 10))
        let segments = DiffVisibility(rows: rows).segments()
        guard case .gap(let middle) = segments[2] else { Issue.record("\(segments)"); return }
        #expect(middle.rows == 9..<47 && !middle.isAtTop && !middle.isAtEnd)
        #expect(middle.label == "38 unchanged lines")
        #expect(middle.expanders.map(\.kind) == [.showBelow, .showAbove, .showAll])
        #expect(middle.expanders.map(\.rows) == [9..<24, 32..<47, 9..<47])
    }

    @Test func smallGapsOfferOnlyShowAllAndOverlappingContextMerges() {
        // Changes at 10 and 24: rows 7...13 and 21...27, a gap of 7 between.
        let apart = Fixtures.rows(String(repeating: "c", count: 10) + "a" + String(repeating: "c", count: 13) + "a" + String(repeating: "c", count: 3))
        let segments = DiffVisibility(rows: apart).segments()
        #expect(segments.map(Self.shape) == ["gap 0..<7", "rows 7..<14", "gap 14..<21", "rows 21..<28"])
        guard case .gap(let gap) = segments[2] else { return }
        #expect(gap.label == "7 unchanged lines")
        #expect(gap.expanders.map(\.title) == ["Show all"])

        // A gap of exactly 30 still offers only Show all.
        let thirty = Fixtures.rows("a" + String(repeating: "c", count: 36) + "a")
        guard case .gap(let edge) = DiffVisibility(rows: thirty).segments()[1] else { return }
        #expect(edge.count == 30 && edge.expanders.map(\.kind) == [.showAll])

        // Changes at 10 and 17: their context touches, so one run of rows.
        let close = Fixtures.rows(String(repeating: "c", count: 10) + "a" + String(repeating: "c", count: 6) + "a" + String(repeating: "c", count: 3))
        #expect(DiffVisibility(rows: close).segments().map(Self.shape) == ["gap 0..<7", "rows 7..<21"])

        // One hidden line reads in the singular.
        let single = Fixtures.rows("a" + String(repeating: "c", count: 4))
        guard case .gap(let one) = DiffVisibility(rows: single).segments().last else { return }
        #expect(one.label == "1 unchanged line to the end")
    }

    @Test func revealsUnionWithTheBaseSet() {
        var visibility = DiffVisibility(rows: Self.oneChange)
        guard case .gap(let end) = visibility.segments()[2] else { return }
        visibility.reveal(end.expanders[0])
        #expect(visibility.segments().map(Self.shape) == ["gap 0..<37", "rows 37..<60", "gap 60..<100"])
        guard case .gap(let top) = visibility.segments()[0] else { return }
        visibility.reveal(top.expanders[0])
        #expect(visibility.segments().map(Self.shape) == ["gap 0..<22", "rows 22..<60", "gap 60..<100"])
        guard case .gap(let rest) = visibility.segments()[2] else { return }
        visibility.reveal(rest.expanders.last!)
        #expect(visibility.segments().map(Self.shape) == ["gap 0..<22", "rows 22..<100"])
        // Out-of-range reveals clamp instead of trapping.
        visibility.reveal(-5..<3)
        #expect(visibility.segments().map(Self.shape) == ["rows 0..<3", "gap 3..<22", "rows 22..<100"])
    }

    @Test func wholeFileShowsEveryRow() {
        let visibility = DiffVisibility(rows: Self.oneChange)
        #expect(visibility.segments(wholeFile: true) == [.rows(0..<100)])
        #expect(visibility.isVisible(0, wholeFile: true) && !visibility.isVisible(0))
    }

    @Test func excerptKeepsDeletionsAfterInsideLinesOnly() {
        // d(old 1) c(1) c(2) d(old 4) a(3) c(4) d(old 6) c(5)
        let rows = Fixtures.rows("dccdacdc")
        #expect(rows.map(\.newLine) == [nil, 1, 2, nil, 3, 4, nil, 5])
        let visibility = DiffVisibility(rows: rows, mode: .excerpt(3...4))
        // The deletion before new line 3 follows new line 2 (outside), so it
        // is hidden; the one after new line 4 follows an inside row, so shown.
        #expect(visibility.base == IndexSet([4, 5, 6]))
        let segments = visibility.segments()
        #expect(segments.map(Self.shape) == ["gap 0..<4", "rows 4..<7", "gap 7..<8"])
        guard case .gap(let end) = segments[2] else { return }
        #expect(end.label == "1 unchanged line to the end")
        #expect(visibility.excerptLines == 3...4)

        // A leading deletion is never inside, even when the excerpt starts at 1.
        #expect(!DiffVisibility(rows: rows, mode: .excerpt(1...5)).base.contains(0))
        #expect(DiffVisibility(rows: rows, mode: .excerpt(1...5)).base == IndexSet(integersIn: 1...7))
    }

    @Test func realExcerptOfAnAddedFile() throws {
        // Step 6's `serve_http` excerpt, lines 125 to 223 of a new file.
        let diff = try DiffRows.parse(try Fixtures.text("pr10640/src_shellbox_http_service.py.diff"))
        let visibility = DiffVisibility(rows: diff.rows, mode: .excerpt(125...223))
        let segments = visibility.segments()
        #expect(segments.map(Self.shape) == ["gap 0..<124", "rows 124..<223"])
        guard case .gap(let top) = segments[0] else { return }
        // Every hidden row is an added line, and the demo still says "unchanged".
        #expect(top.label == "124 unchanged lines at the top")
        #expect(top.expanders.map(\.rows) == [109..<124, 0..<124])
    }

    @Test func goToLineRevealsSixBeforeAndFourteenAfter() throws {
        var visibility = DiffVisibility(rows: Self.oneChange)
        #expect(visibility.goTo(newLine: 80, in: Self.oneChange) == 80)
        #expect(visibility.revealed == IndexSet(integersIn: 74...94))
        #expect(visibility.segments().map(Self.shape) == ["gap 0..<37", "rows 37..<45", "gap 45..<74", "rows 74..<95", "gap 95..<100"])

        // Clamped at both ends of the file.
        var edges = DiffVisibility(rows: Self.oneChange)
        #expect(edges.revealAround(row: 2) == 0...16)
        #expect(edges.revealAround(row: 98) == 92...99)

        // A line the head does not have finds no row and reveals nothing.
        var missing = DiffVisibility(rows: Self.oneChange)
        #expect(missing.goTo(newLine: 500, in: Self.oneChange) == nil)
        #expect(missing.revealed.isEmpty)

        // Real data: the review note f5 on line 327 of the local machine.
        let diff = try DiffRows.parse(try Fixtures.text("pr10640/src_shellbox_backends_local_machine.py.diff"))
        var real = DiffVisibility(rows: diff.rows)
        let target = real.goTo(newLine: 327, in: diff.rows)
        let row = try #require(target)
        #expect(diff.rows[row].newLine == 327 && real.isVisible(row))
        #expect(real.isVisible(row - 6) && real.isVisible(row + 14))
    }

    static func shape(_ segment: DiffSegment) -> String {
        switch segment {
        case .rows(let rows): "rows \(rows)"
        case .gap(let gap): "gap \(gap.rows)"
        }
    }
}
