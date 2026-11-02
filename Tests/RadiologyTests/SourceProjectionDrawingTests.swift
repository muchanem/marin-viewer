import AppKit
import Testing
@testable import Radiology

/// The draw-time hook: receded characters take the storage's own syntax
/// color at reduced opacity, everything else passes through, and nothing in
/// the text storage, selection, or folds changes.
@MainActor
struct SourceProjectionDrawingTests {
    static func harness(_ source: String) throws -> (ReaderTextView, SourceViewerCoordinator, SourceBuffer) {
        let view = SourceCaretTests.reader(source)
        let coordinator = SourceViewerCoordinator()
        coordinator.textView = view
        coordinator.buffer = try SourceBuffer(path: "x.rs", data: Data(source.utf8))
        view.layoutManager?.delegate = coordinator
        return (view, coordinator, coordinator.buffer!)
    }

    @Test func recededRangesDimTheStorageColorAndKeepIncomingAttributes() throws {
        let source = "let 🚀 = x.unwrap().clone();\n"
        let (view, coordinator, buffer) = try Self.harness(source)
        let layout = try #require(view.layoutManager)
        let storage = try #require(view.textStorage)
        // Give `unwrap` a syntax color so the hook has a role to dim.
        let unwrapBytes = try #require(source.range(of: "unwrap").map { source.utf8.distance(from: source.startIndex, to: $0.lowerBound) })
        let cloneBytes = try #require(source.range(of: "clone").map { source.utf8.distance(from: source.startIndex, to: $0.lowerBound) })
        let unwrap = buffer.utf16Range(forByteRange: unwrapBytes..<(unwrapBytes + 6))
        let clone = buffer.utf16Range(forByteRange: cloneBytes..<(cloneBytes + 5))
        storage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: unwrap)
        let before = storage.copy() as! NSAttributedString
        view.setSelectedRange(NSRange(location: 0, length: 3))

        let projection = SourceProjection(path: "x.rs", sourceIdentity: SourceContentIdentity(buffer.data),
                                          recededByteRanges: [cloneBytes..<(cloneBytes + 5), unwrapBytes..<(unwrapBytes + 6)])
        coordinator.applyProjection(projection, buffer: buffer)
        #expect(coordinator.recededCharacterRanges == [unwrap, clone], "UTF-16 ranges after the emoji, sorted")

        func hook(_ index: Int, attrs: [NSAttributedString.Key: Any] = [:], effective: NSRange? = nil) -> ([NSAttributedString.Key: Any]?, NSRange) {
            var range = effective ?? NSRange(location: 0, length: 0)
            let result = coordinator.layoutManager(layout, shouldUseTemporaryAttributes: attrs, forDrawingToScreen: true,
                                                   atCharacterIndex: index, effectiveRange: &range)
            return (result, range)
        }
        // Inside `unwrap`: the storage's blue at reduced alpha, bounded to the run.
        let (dimmed, dimmedRange) = hook(unwrap.location + 2)
        let color = try #require(dimmed?[.foregroundColor] as? NSColor)
        let expectedAlpha = Theme.recededSourceAlpha(appearance: view.effectiveAppearance)
        #expect(abs(color.alphaComponent - expectedAlpha) < 0.001)
        #expect(color.withAlphaComponent(1).usingColorSpace(.sRGB)?.blueComponent == NSColor.systemBlue.usingColorSpace(.sRGB)?.blueComponent)
        #expect(dimmedRange == NSRange(location: unwrap.location + 2, length: unwrap.length - 2) || dimmedRange == unwrap)
        // Incoming hover attributes survive.
        let underline: [NSAttributedString.Key: Any] = [.underlineStyle: NSUnderlineStyle.single.rawValue]
        let (merged, _) = hook(clone.location, attrs: underline, effective: clone)
        #expect(merged?[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect((merged?[.foregroundColor] as? NSColor)?.alphaComponent ?? 1 < 1)
        // Outside: pass-through, and the effective range stops before the next receded run.
        let (plain, plainRange) = hook(0)
        #expect(plain == nil)
        #expect(NSMaxRange(plainRange) == unwrap.location)
        let (plainWithAttrs, _) = hook(0, attrs: underline, effective: NSRange(location: 0, length: 3))
        #expect(plainWithAttrs?[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(plainWithAttrs?[.foregroundColor] == nil)
        // The effective range never exceeds what TextKit asked about.
        let (_, bounded) = hook(unwrap.location, effective: NSRange(location: unwrap.location, length: 2))
        #expect(bounded == NSRange(location: unwrap.location, length: 2))
        // Not drawing to screen (printing/pasteboard paths): untouched.
        var any = NSRange(location: 0, length: 0)
        #expect(coordinator.layoutManager(layout, shouldUseTemporaryAttributes: [:], forDrawingToScreen: false, atCharacterIndex: unwrap.location, effectiveRange: &any) == nil)

        // Nothing in the storage or selection changed, and copy sees the original text.
        #expect(storage.isEqual(to: before))
        #expect(view.selectedRange() == NSRange(location: 0, length: 3))
        #expect(view.string == source)

        // Same projection: no-op; a new one replaces; nil clears.
        coordinator.applyProjection(projection, buffer: buffer)
        #expect(coordinator.recededCharacterRanges == [unwrap, clone])
        coordinator.applyProjection(nil, buffer: buffer)
        #expect(coordinator.recededCharacterRanges.isEmpty)
        let (cleared, _) = hook(unwrap.location + 1)
        #expect(cleared == nil)
    }

    @Test func rangesClearOnSourceReplacementAndSurviveAFoldAndRedraw() throws {
        let source = "fn scan() {\n    work().clone();\n}\n"
        let (view, coordinator, buffer) = try Self.harness(source)
        let cloneBytes = try #require(source.range(of: "clone").map { source.utf8.distance(from: source.startIndex, to: $0.lowerBound) })
        let projection = SourceProjection(path: "x.rs", sourceIdentity: SourceContentIdentity(buffer.data), recededByteRanges: [cloneBytes..<(cloneBytes + 5)])
        coordinator.applyProjection(projection, buffer: buffer)
        #expect(coordinator.recededCharacterRanges.count == 1)
        // Folding the body hides `clone`; the projection is unchanged and drawing does not throw.
        let open = source.utf8.distance(from: source.utf8.startIndex, to: try #require(source.utf8.firstIndex(of: UInt8(ascii: "{"))))
        let close = source.utf8.distance(from: source.utf8.startIndex, to: try #require(source.utf8.firstIndex(of: UInt8(ascii: "}")))) + 1
        let snapshot = SyntaxSnapshot(path: "x.rs", languageID: "rust", languageName: "Rust", highlights: [],
                                      folds: [SourceFold(kind: "function", byteRange: open..<close)], symbols: [], scopes: [], hasParseErrors: false)
        _ = coordinator.updateSyntax(snapshot, buffer: buffer, resetFolds: true)
        coordinator.applyFoldAttributes()
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: image)
        #expect(coordinator.recededCharacterRanges.count == 1)
        #expect(coordinator.isFolded(snapshot.folds[0]))
        // A source replacement drops the ranges until a matching projection is applied again.
        coordinator.prepareForSourceReplacement()
        #expect(coordinator.recededCharacterRanges.isEmpty)
        coordinator.finishSourceReplacement()
        coordinator.applyProjection(projection, buffer: buffer)
        #expect(coordinator.recededCharacterRanges.count == 1, "the same projection id is reapplied after replacement")
    }

    /// Temporary attributes (and so this hook's colors) are honored by TextKit
    /// only when drawing to the screen, so an offscreen bitmap cannot show the
    /// dimming; the visual check is a live one. What a test can prove is that
    /// every draw pass consults the hook for the drawn runs.
    @Test func drawingConsultsTheHookForEveryPass() throws {
        let source = "unwrap unwrap\n"
        let (view, coordinator, buffer) = try Self.harness(source)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        defer { window.contentView = nil }
        func draw() throws {
            let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: image)
        }
        try draw()
        let withoutProjection = coordinator.projectionHookCalls
        #expect(withoutProjection > 0, "consulted even with no projection and no temporary attributes")
        coordinator.applyProjection(SourceProjection(path: "x.rs", sourceIdentity: SourceContentIdentity(buffer.data), recededByteRanges: [7..<13]), buffer: buffer)
        try draw()
        #expect(coordinator.projectionHookCalls > withoutProjection)
        view.display()
        #expect(coordinator.projectionHookCalls > withoutProjection + 1)
    }
}
