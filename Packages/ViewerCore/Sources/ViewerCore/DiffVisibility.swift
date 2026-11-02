import Foundation

/// Which rows of one file card are on screen. A port of the demo's
/// `diffVisible`, `rangeVisible` and `renderLines`: a base set chosen by the
/// card's mode, plus rows the reader revealed through gap expanders or Go to
/// Line. Row indices index the card's `FileDiff.rows`.
///
/// The demo keys reveals per card (`f:<path>` in By file mode,
/// `s<step>:<excerpt>` in By step mode) and Whole file per path, so a
/// SwiftUI model keeps one `DiffVisibility` per card and passes the path's
/// Whole file flag into `segments(wholeFile:)` and `isVisible(_:wholeFile:)`.
///
/// Two rules differ from the demo on purpose, and `DemoParityTests` states
/// both: a gap that hides changed rows is not called "unchanged", and an
/// excerpt shows the deletions just before its first line as well as those
/// just after its last line.
public struct DiffVisibility: Hashable, Sendable {
    public enum Mode: Hashable, Sendable {
        /// Changed rows plus `contextLines` rows either side (`diffVisible`).
        case diff
        /// The rows of a step excerpt, by new-side line (`rangeVisible`).
        case excerpt(ClosedRange<Int>)
    }

    /// The demo's `CONTEXT`.
    public static let contextLines = 3
    /// Rows one "Show 15 above" or "Show 15 below" reveals.
    public static let revealStep = 15
    /// Gaps longer than this offer Show 15 above and below besides Show all.
    public static let stepThreshold = 30
    /// Go to Line reveals this many rows before the target row…
    public static let goToRowsBefore = 6
    /// …and this many after it.
    public static let goToRowsAfter = 14

    public let mode: Mode
    public let rowCount: Int
    /// Rows the mode shows by itself.
    public let base: IndexSet
    /// Rows revealed since: the demo's `S.reveal[key]`.
    public private(set) var revealed: IndexSet
    /// Added and deleted rows, so a gap can say whether it hides any.
    public let changed: IndexSet
    /// Added rows, so a gap can say which kind of change it hides.
    public let added: IndexSet

    public init(rows: [DiffRow], mode: Mode = .diff) {
        self.mode = mode
        rowCount = rows.count
        revealed = IndexSet()
        changed = IndexSet(rows.indices.filter { rows[$0].isChange })
        added = IndexSet(rows.indices.filter { rows[$0].kind == .added })
        switch mode {
        case .diff: base = Self.diffRows(rows)
        case .excerpt(let lines): base = Self.excerptRows(rows, lines: lines)
        }
    }

    /// The excerpt's new-side lines, or nil in diff mode. The demo's
    /// `goToLineInStep` flashes a row in place when the excerpt holds the
    /// line and otherwise falls back to Go to Line in By file mode.
    public var excerptLines: ClosedRange<Int>? {
        if case .excerpt(let lines) = mode { return lines }
        return nil
    }

    public func isVisible(_ row: Int, wholeFile: Bool = false) -> Bool {
        wholeFile || base.contains(row) || revealed.contains(row)
    }

    /// The card's rows in order: runs of visible rows and the gaps between
    /// them, as `renderLines` draws them.
    public func segments(wholeFile: Bool = false) -> [DiffSegment] {
        var segments: [DiffSegment] = []
        var row = 0
        while row < rowCount {
            let shown = isVisible(row, wholeFile: wholeFile)
            var end = row + 1
            while end < rowCount, isVisible(end, wholeFile: wholeFile) == shown { end += 1 }
            let range = row..<end
            segments.append(shown ? .rows(range) : .gap(DiffGap(
                rows: range, rowCount: rowCount, changedRows: changed.count(in: range), addedRows: added.count(in: range))))
            row = end
        }
        return segments
    }

    public mutating func reveal(_ rows: Range<Int>) {
        let clamped = rows.clamped(to: 0..<rowCount)
        if !clamped.isEmpty { revealed.insert(integersIn: clamped) }
    }

    public mutating func reveal(_ expander: GapExpander) { reveal(expander.rows) }

    /// Reveals the rows Go to Line shows around `row` (6 before, 14 after,
    /// clamped to the file) and returns them.
    @discardableResult
    public mutating func revealAround(row: Int) -> ClosedRange<Int> {
        precondition((0..<rowCount).contains(row), "row \(row) is outside the card's \(rowCount) rows")
        let rows = max(0, row - Self.goToRowsBefore)...min(rowCount - 1, row + Self.goToRowsAfter)
        reveal(rows.lowerBound..<(rows.upperBound + 1))
        return rows
    }

    /// Go to Line on this card: finds the row for new-side `line`, reveals
    /// the rows around it, and returns the row to scroll to and flash. Nil
    /// when no row has that new line (the demo then reveals rows 0 to 13,
    /// because `findIndex` returns -1; this port reveals nothing).
    @discardableResult
    public mutating func goTo(newLine line: Int, in rows: [DiffRow]) -> Int? {
        guard let row = rows.firstIndex(where: { $0.newLine == line }) else { return nil }
        revealAround(row: row)
        return row
    }

    // MARK: - Base sets

    private static func diffRows(_ rows: [DiffRow]) -> IndexSet {
        var visible = IndexSet()
        for (index, row) in rows.enumerated() where row.isChange {
            let lower = max(0, index - contextLines), upper = min(rows.count - 1, index + contextLines)
            visible.insert(integersIn: lower...upper)
        }
        return visible
    }

    /// A row with a new line is inside when the excerpt holds that line. A
    /// run of deleted rows is inside when the row with a new line on either
    /// side of it is, so deletions just before the excerpt's first line and
    /// just after its last line both show. The demo's `rangeVisible` looked
    /// only at the row before, which hid deletions at the top of an excerpt.
    private static func excerptRows(_ rows: [DiffRow], lines: ClosedRange<Int>) -> IndexSet {
        var visible = IndexSet()
        var previousInside = false
        var index = 0
        while index < rows.count {
            if let line = rows[index].newLine {
                previousInside = lines.contains(line)
                if previousInside { visible.insert(index) }
                index += 1
                continue
            }
            var end = index
            while end < rows.count, rows[end].newLine == nil { end += 1 }
            let nextInside = end < rows.count && rows[end].newLine.map(lines.contains) == true
            if previousInside || nextInside { visible.insert(integersIn: index..<end) }
            index = end
        }
        return visible
    }
}

public enum DiffSegment: Hashable, Sendable {
    /// Consecutive visible rows.
    case rows(Range<Int>)
    case gap(DiffGap)
}

/// A run of hidden rows, drawn as one bar with a count and expanders.
public struct DiffGap: Hashable, Sendable {
    public let rows: Range<Int>
    /// The gap starts at the file's first row.
    public let isAtTop: Bool
    /// The gap runs to the file's last row.
    public let isAtEnd: Bool
    /// Added and deleted rows among the hidden ones. Only excerpt cards hide
    /// changes; a diff card shows every change with its context.
    public let changedRows: Int
    /// Added rows among the changed ones; the rest are deletions.
    public let addedRows: Int

    public init(rows: Range<Int>, rowCount: Int, changedRows: Int = 0, addedRows: Int = 0) {
        self.rows = rows
        isAtTop = rows.lowerBound == 0
        isAtEnd = rows.upperBound == rowCount
        self.changedRows = changedRows
        self.addedRows = min(addedRows, changedRows)
    }

    public var count: Int { rows.count }

    /// "12 unchanged lines", "1 unchanged line at the top", "40 unchanged
    /// lines to the end". A gap that is both at the top and at the end says
    /// "at the top". A gap of one kind of row names the kind: "124 added
    /// lines at the top", "3 deleted lines", "5 changed lines" when it holds
    /// both. A gap of context and changes counts the changes: "40 lines, 12
    /// changed". The demo called every gap unchanged.
    public var label: String {
        let place = isAtTop ? " at the top" : isAtEnd ? " to the end" : ""
        let lines = count == 1 ? "line" : "lines"
        let kind: String
        switch changedRows {
        case 0: kind = "unchanged"
        case count: kind = addedRows == count ? "added" : addedRows == 0 ? "deleted" : "changed"
        default: return "\(count) \(lines)\(place), \(changedRows) changed"
        }
        return "\(count) \(kind) \(lines)\(place)"
    }

    /// In the demo's order: Show 15 below, Show 15 above, Show all. Gaps of
    /// 30 rows or fewer offer only Show all; a gap at the top has no Show 15
    /// below and a gap at the end no Show 15 above.
    public var expanders: [GapExpander] {
        var expanders: [GapExpander] = []
        if count > DiffVisibility.stepThreshold {
            let step = DiffVisibility.revealStep
            if !isAtTop { expanders.append(GapExpander(kind: .showBelow, rows: rows.lowerBound..<(rows.lowerBound + step))) }
            if !isAtEnd { expanders.append(GapExpander(kind: .showAbove, rows: (rows.upperBound - step)..<rows.upperBound)) }
        }
        expanders.append(GapExpander(kind: .showAll, rows: rows))
        return expanders
    }
}

/// One button on a gap bar and the rows it reveals.
public struct GapExpander: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// The first 15 hidden rows, just below the visible rows above the gap.
        case showBelow
        /// The last 15 hidden rows, just above the visible rows below the gap.
        case showAbove
        case showAll
    }

    public let kind: Kind
    public let rows: Range<Int>

    public var title: String {
        switch kind {
        case .showBelow: "Show \(DiffVisibility.revealStep) below"
        case .showAbove: "Show \(DiffVisibility.revealStep) above"
        case .showAll: "Show all"
        }
    }
}
