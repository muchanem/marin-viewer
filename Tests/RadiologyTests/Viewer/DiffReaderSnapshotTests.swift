import AppKit
import SwiftUI
import Testing
import ViewerCore
@testable import Radiology

/// Renders the reader for #10640 in the states the demo screenshots show,
/// hosted in an `NSHostingView` inside a window and captured with
/// `cacheDisplay`. Set `DIFF_READER_SNAPSHOT_DIR` to keep the PNGs.
@MainActor
@Suite(.serialized, .enabled(if: ViewerFixture.isAvailable, "needs marin/ and wordbase/ beside the checkout"))
struct DiffReaderSnapshotTests {
    /// The demo's main column at a 1440-point window: 1440 − 270 − 390.
    static let width: CGFloat = 780
    static let height: CGFloat = 1100

    @Test func byStepAtSteps1And6And7() async throws {
        for step in [1, 6, 7] {
            let model = DiffReaderModel(document: try await ViewerFixture.document())
            model.focus(step: step)
            let image = try await render(model, name: "app-step\(step).png")
            #expect(Self.inkFraction(image) > 0.01, "step \(step) rendered blank")
        }
    }

    @Test func byFileOnHTTPServiceWithBlame() async throws {
        let model = DiffReaderModel(document: try await ViewerFixture.document())
        model.now = ViewerFixture.demoNow
        model.mode = .byFile
        model.showBlame = true
        model.revealFile(DiffReaderModelTests.http)
        await model.loadBlames()
        let image = try await render(model, name: "app-byfile-http-blame.png")
        #expect(Self.inkFraction(image) > 0.01)
    }

    @Test func noteExpandedBelowItsRow() async throws {
        let model = DiffReaderModel(document: try await ViewerFixture.document())
        model.focus(step: 6)
        model.focus(note: "f1")
        #expect(model.expandedNoteID == "f1")
        let image = try await render(model, name: "app-note-f1.png")
        #expect(Self.inkFraction(image) > 0.01)
    }

    // MARK: - Rendering

    private func render(_ model: DiffReaderModel, name: String) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: DiffReaderView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        host.frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.height)
        window.contentView = host
        defer { window.contentView = nil }
        // Layout, then the reader's scroll requests, which run on the next
        // turns of the main queue.
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
        }
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let directory = ViewerFixture.snapshotDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appending(path: name))
        }
        return bitmap
    }

    /// Share of sampled pixels darker than the page in the lower right of
    /// the render, where code is drawn: a guard against blank card bodies.
    static func inkFraction(_ bitmap: NSBitmapImageRep) -> Double {
        var dark = 0, total = 0
        for y in stride(from: bitmap.pixelsHigh / 2, to: bitmap.pixelsHigh * 9 / 10, by: 5) {
            for x in stride(from: bitmap.pixelsWide * 2 / 5, to: bitmap.pixelsWide * 9 / 10, by: 3) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                total += 1
                let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
                if luminance < 0.6 { dark += 1 }
            }
        }
        return total == 0 ? 0 : Double(dark) / Double(total)
    }
}
