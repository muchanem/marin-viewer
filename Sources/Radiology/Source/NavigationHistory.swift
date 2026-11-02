import Foundation

struct NavigationHistory {
    private(set) var entries: [SourceLocation] = []
    private(set) var index = -1
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index >= 0 && index + 1 < entries.count }
    var current: SourceLocation? { index >= 0 && index < entries.count ? entries[index] : nil }

    mutating func visit(_ location: SourceLocation) {
        if index >= 0 && entries[index] == location { return }
        entries = Array(entries.prefix(index + 1))
        entries.append(location)
        index = entries.count - 1
    }
    mutating func updateCurrent(_ location: SourceLocation) {
        if index >= 0 { entries[index] = location }
    }
    mutating func back() -> SourceLocation? {
        guard canGoBack else { return nil }
        index -= 1
        return entries[index]
    }
    mutating func forward() -> SourceLocation? {
        guard canGoForward else { return nil }
        index += 1
        return entries[index]
    }
}
