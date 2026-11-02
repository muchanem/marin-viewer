import AppKit
import Testing
@testable import Radiology

@MainActor
struct HoverPopoverInteractionTests {
    static func presentation(definition: SemanticPosition?) -> CriticalSummaryModel.HoverPresentation {
        CriticalSummaryModel.HoverPresentation(id: UUID(), symbol: SemanticSymbolID(symbol: "rust-analyzer cargo repo 1 section().", document: ""),
            displayName: "section", byteRange: 0..<7, phase: .loading, definition: definition, externalPackage: nil)
    }

    @Test func nativeHostTracksPaddingAndKeepsItsViewWhenResultsChange() throws {
        let host = HoverPopoverHost(presentation: Self.presentation(definition: nil), navigate: { _, _ in }, hovered: { _ in })
        let view = host.view
        let tracking = try #require(view.trackingAreas.first { $0.owner === host })
        #expect(tracking.options.contains(.activeAlways))
        #expect(tracking.options.contains(.inVisibleRect))
        #expect(tracking.options.contains(.mouseEnteredAndExited))
        let id = host.content.presentation.id
        host.content.presentation = CriticalSummaryModel.HoverPresentation(id: id, symbol: host.content.presentation.symbol,
            displayName: "section", byteRange: 0..<7, phase: .loaded(CriticalSummaryModel.externalFrontier(host.content.presentation.symbol)),
            definition: nil, externalPackage: "core")
        #expect(host.view === view, "result publication must not replace pointer tracking or button hit targets")
    }

    @Test func nativeEnterExitRoutesAndTransitCoversGapWithoutCapturingDistantText() throws {
        var inside: [Bool] = []
        let host = HoverPopoverHost(presentation: Self.presentation(definition: nil), navigate: { _, _ in }, hovered: { inside.append($0) })
        let enter = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        let exit = try #require(NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        host.mouseEntered(with: enter)
        host.mouseExited(with: exit)
        #expect(inside == [true, false])
        let anchor = NSRect(x: 200, y: 200, width: 50, height: 18)
        let popup = NSRect(x: 150, y: 240, width: 380, height: 120)
        #expect(ReaderTextView.hoverTransitContains(NSPoint(x: 220, y: 230), anchor: anchor, popover: popup))
        #expect(ReaderTextView.hoverTransitContains(NSPoint(x: 400, y: 280), anchor: anchor, popover: popup))
        #expect(!ReaderTextView.hoverTransitContains(NSPoint(x: 600, y: 180), anchor: anchor, popover: popup))
    }
}
