import Testing
@testable import Radiology

struct NavigationHistoryTests {
    @Test func backForwardRestoreLocationsAndNewVisitsDiscardFuture() {
        var history = NavigationHistory()
        let a = SourceLocation(path: "a.swift", byteOffset: 0)
        let b = SourceLocation(path: "b.swift", byteOffset: 20)
        let aScrolled = SourceLocation(path: "a.swift", byteOffset: 100)
        history.visit(a)
        history.updateCurrent(aScrolled)
        history.visit(b)
        history.visit(b)
        #expect(history.entries.count == 2)
        #expect(history.back() == aScrolled)
        #expect(history.forward() == b)
        #expect(history.back() == aScrolled)
        history.visit(SourceLocation(path: "c.swift", byteOffset: 0))
        #expect(!history.canGoForward)
        #expect(history.back() == aScrolled)
        #expect(history.back() == nil)
    }
}
