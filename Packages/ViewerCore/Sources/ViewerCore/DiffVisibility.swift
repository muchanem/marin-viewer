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

    public init(rows: [DiffRow], mode: Mode = .diff) {
        self.mode = mode
        rowCount = rows.count
        revealed = IndexSet()
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
            segments.append(shown ? .rows(row..<end) : .gap(DiffGap(rows: row..<end, rowCount: rowCount)))
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

    /// A row with a new line is inside when the excerpt holds that line; a
    /// deleted row takes the answer of the last row before it that had one.
    /// So deletions just after the excerpt's last line are shown, those just
    /// before its first line are not, and leading deletions never are.
    private static func excerptRows(_ rows: [DiffRow], lines: ClosedRange<Int>) -> IndexSet {
        var visible = IndexSet()
        var inside = false
        for (index, row) in rows.enumerated() {
            if let line = row.newLine { inside = lines.contains(line) }
            if inside { visible.insert(index) }
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

    public init(rows: Range<Int>, rowCount: Int) {
        self.rows = rows
        isAtTop = rows.lowerBound == 0
        isAtEnd = rows.upperBound == rowCount
    }

    public var count: Int { rows.count }

    /// "12 unchanged lines", "1 unchanged line at the top", "40 unchanged
    /// lines to the end". A gap that is both at the top and at the end says
    /// "at the top". In an excerpt card the hidden rows can include changes;
    /// the demo still calls them unchanged.
    public var label: String {
        let place = isAtTop ? " at the top" : isAtEnd ? " to the end" : ""
        return "\(count) unchanged line\(count == 1 ? "" : "s")\(place)"
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
