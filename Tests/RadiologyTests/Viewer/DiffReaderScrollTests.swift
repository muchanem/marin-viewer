import AppKit
import SwiftUI
import Testing
@testable import Radiology

/// A revealed row ends up centred in the reader, whether its card was already on screen or
/// the reveal had to switch modes first. A SwiftUI scroll to the card used to land after the
/// card body's own scroll and leave the card's top in view.
@Suite(.serialized) @MainActor
struct DiffReaderScrollTests {
    @Test func aRevealedRowIsCentredInAMountedCardAndAfterAModeSwitch() async throws {
        guard ViewerFixture.isAvailable else { return }
        let model = DiffReaderModel(document: try await ViewerFixture.document())
        model.revealFile(DiffReaderModelTests.http)
        let host = NSHostingView(rootView: DiffReaderView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.close() }
        func settle() async throws {
            for _ in 0..<10 {
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        var bodies: [DiffCardBodyView] = []
        var outer: NSScrollView?
        func find(_ view: NSView) {
            if let body = view as? DiffCardBodyView { bodies.append(body) }
            if outer == nil, let scroll = view as? NSScrollView, !(scroll is DiffHorizontalScrollView) { outer = scroll }
            view.subviews.forEach(find)
        }
        /// Where `line` sits in the reader's visible rect: 0 at the top, 1 at the bottom.
        func position(of line: Int) throws -> CGFloat {
            bodies = []
            outer = nil
            find(host)
            let scroll = try #require(outer)
            let body = try #require(bodies.first { $0.text.content?.card.path == DiffReaderModelTests.http })
            let content = try #require(body.text.content)
            let file = try #require(model.document.file(DiffReaderModelTests.http))
            let row = try #require(file.diff.rowIndex(forNewLine: line))
            let index = try #require(content.rows.lineIndex(ofRow: row))
            let rect = try #require(body.layoutCache).rect(ofLine: index, width: body.bounds.width)
            let inDocument = body.convert(rect, to: scroll.documentView)
            let visible = scroll.contentView.bounds
            return (inDocument.midY - visible.minY) / visible.height
        }

        try await settle()
        #expect(try position(of: 1) < 0.2)
        model.focus(note: "f1")
        try await settle()
        let mounted = try position(of: 133)
        #expect(mounted > 0.3 && mounted < 0.7, "line 133 at \(mounted) of the view")

        model.closeNote()
        model.focus(step: 1)
        try await settle()
        model.focus(note: "f1")
        try await settle()
        #expect(model.mode == .byFile)
        let switched = try position(of: 133)
        #expect(switched > 0.3 && switched < 0.7, "line 133 at \(switched) of the view")
    }
}
