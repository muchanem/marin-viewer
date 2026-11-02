import Foundation
import Testing
@testable import Radiology

/// The Context inspector's model against the real rust-analyzer fixture index
/// (and one synthetic UTF-16 index), driven directly through `update`.
@MainActor
struct ContextModelTests {
    struct Fixture {
        let root: URL
        let index: SemanticIndex
        let lib: SourceBuffer
        let shapes: SourceBuffer
        let libSyntax: SyntaxSnapshot
        let shapesSyntax: SyntaxSnapshot
    }

    static func fixture() async throws -> Fixture {
        let root = try IndexingTests.temporaryRepository()
        let (_, index) = try SemanticIndexTests.loadFixture()
        let lib = try SourceBuffer(path: "src/lib.rs", data: Data(contentsOf: root.appending(path: "src/lib.rs")))
        let shapes = try SourceBuffer(path: "src/shapes.rs", data: Data(contentsOf: root.appending(path: "src/shapes.rs")))
        let worker = SyntaxWorker()
        let libSyntax = try #require(try await worker.parse(lib))
        let shapesSyntax = try #require(try await worker.parse(shapes))
        return Fixture(root: root, index: index, lib: lib, shapes: shapes, libSyntax: libSyntax, shapesSyntax: shapesSyntax)
    }

    static func inputs(_ fixture: Fixture, buffer: SourceBuffer, syntax: SyntaxSnapshot?, caret: Int?,
                       root: URL? = nil, indexRevision: Int = 1, documentRevision: Int = 1) -> ContextInputs {
        ContextInputs(root: root ?? fixture.root, buffer: buffer, sourceIdentity: SourceContentIdentity(buffer.data),
                      syntax: syntax, caretByte: caret, index: fixture.index, indexRevision: indexRevision,
                      documentSemantics: fixture.index.documents[buffer.path].map { DocumentSemantics.make(document: $0, buffer: buffer) },
                      documentRevision: documentRevision)
    }

    static func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(condition(), "timed out")
    }

    static func isLoaded(_ phase: ContextModel.ReferencePhase) -> Bool {
        if case .loaded = phase { true } else { false }
    }

    static func loadedPreview(_ phase: ContextModel.PreviewPhase) -> DefinitionPreview? {
        if case .loaded(let preview) = phase { preview } else { nil }
    }

    // MARK: - Identity stability

    @Test func underCaretIdentityIgnoresMovementWithinOneOccurrence() async throws {
        let f = try await Self.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let context = ContextModel()
        // `pub fn total_area(items: &[Circle]) -> f64 {`: `Circle` is columns 27..<33.
        let circle = f.lib.byteOffset(line: 5, column: 27)
        context.update(Self.inputs(f, buffer: f.lib, syntax: f.libSyntax, caret: circle))
        #expect(context.underCaret?.target.displayName == "Circle")
        #expect(context.declaration?.declaration.name == "total_area")
        #expect(context.underCaretBuildCount == 1)
        #expect(context.declarationBuildCount == 1)
        // Circle is defined in another file: its preview is a disk read.
        try await Self.waitUntil { Self.loadedPreview(context.preview) != nil }
        #expect(context.previewQueryCount == 1)
        #expect(Self.loadedPreview(context.preview)?.lines.first?.text == "pub struct Circle {")
        #expect(Self.loadedPreview(context.preview)?.path == "src/shapes.rs")
        let referencesBefore = context.referenceQueryCount

        // Arrowing through the rest of the token changes nothing observable.
        for byte in circle + 1..<circle + 6 {
            context.update(Self.inputs(f, buffer: f.lib, syntax: f.libSyntax, caret: byte))
        }
        #expect(context.underCaretBuildCount == 1)
        #expect(context.previewQueryCount == 1)
        #expect(context.declarationBuildCount == 1)
        #expect(context.referenceQueryCount == referencesBefore)

        // `item.area()` on line 8 is a different identity inside the same declaration.
        context.update(Self.inputs(f, buffer: f.lib, syntax: f.libSyntax, caret: f.lib.byteOffset(line: 8, column: 21)))
        #expect(context.underCaret?.target.displayName == "area")
        #expect(context.underCaretBuildCount == 2)
        #expect(context.declarationBuildCount == 1, "the enclosing declaration did not change")
        #expect(context.referenceQueryCount == referencesBefore)
        try await Self.waitUntil { Self.loadedPreview(context.preview)?.startLine == 7 }
        #expect(Self.loadedPreview(context.preview)?.lines.first?.text.contains("pub fn area(&self) -> f64") == true)
        // Structurally bounded in the other file: `area` ends on line 10; the
        // impl's closing brace on line 11 (no blank line between) is excluded.
        #expect(Self.loadedPreview(context.preview)?.lines.map(\.number) == [7, 8, 9, 10])
        #expect(Self.loadedPreview(context.preview)?.isTruncated == false)

        // Returning to Circle reuses the cached preview: a new identity, no new read.
        let queries = context.previewQueryCount
        context.update(Self.inputs(f, buffer: f.lib, syntax: f.libSyntax, caret: circle + 3))
        #expect(context.underCaretBuildCount == 3)
        #expect(context.previewQueryCount == queries)
        #expect(Self.loadedPreview(context.preview)?.startLine == 1)
    }

    @Test func declarationReferencesSurviveUnderCaretChangesAndKeepTheirSelection() async throws {
        let f = try await Self.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let context = ContextModel()
        let insideArea = f.shapes.byteOffset(line: 8, column: 12)   // `r` in `let r = self.radius;`
        context.update(Self.inputs(f, buffer: f.shapes, syntax: f.shapesSyntax, caret: insideArea))
        #expect(context.declaration?.declaration.name == "area")
        #expect(context.declaration?.signature == "pub fn area(&self) -> f64")
        #expect(context.declaration?.displayKind == "Method")
        try await Self.waitUntil { Self.isLoaded(context.references) }
        guard case .loaded(let results) = context.references else { return }
        #expect(results.displayName == "area")
        #expect(results.referenceCount == 1)
        #expect(results.definitionCount == 1)
        let call = try #require(results.groups.first { $0.path == "src/lib.rs" }?.hits.first)
        #expect(call.line == 8 && call.match == "area" && !call.isDefinition)
        #expect(call.context.map(\.number) == [6, 7, 8, 9, 10])
        context.selectedReferenceID = call.id
        let queries = context.referenceQueryCount

        // Many under-caret identities inside `area`: `r`, `self`, `radius`, `PI`, whitespace.
        for (line, column) in [(8, 16), (8, 22), (9, 26), (9, 2), (8, 13)] {
            context.update(Self.inputs(f, buffer: f.shapes, syntax: f.shapesSyntax,
                                       caret: f.shapes.byteOffset(line: line, column: column)))
        }
        #expect(context.underCaretBuildCount > 1)
        #expect(context.declarationBuildCount == 1)
        #expect(context.referenceQueryCount == queries)
        #expect(context.selectedReferenceID == call.id, "the reference selection is not disturbed")
        #expect(context.selectedReference == call)

        // Moving into `new` is a different declaration: new references, selection cleared.
        context.update(Self.inputs(f, buffer: f.shapes, syntax: f.shapesSyntax, caret: f.shapes.byteOffset(line: 6, column: 40)))
        #expect(context.declaration?.declaration.name == "new")
        #expect(context.selectedReferenceID == nil)
        try await Self.waitUntil { Self.isLoaded(context.references) }
        // Back to `area`: references come from the cache, not another scan.
        let afterNew = context.referenceQueryCount
        context.update(Self.inputs(f, buffer: f.shapes, syntax: f.shapesSyntax, caret: insideArea))
        #expect(context.referenceQueryCount == afterNew)
        #expect(Self.isLoaded(context.references))
    }

    @Test func implBlocksFollowTheirRealSCIPTypeReference() async throws {
        let f = try await Self.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let context = ContextModel()
        // Line 11 is the closing brace of `impl Circle`, outside both methods.
        context.update(Self.inputs(f, buffer: f.shapes, syntax: f.shapesSyntax, caret: f.shapes.byteOffset(line: 11, column: 0)))
        #expect(context.declaration?.declaration.kind == "extension")
        let circle = SemanticSymbolID(symbol: "rust-analyzer cargo ra_fixture 0.1.0 shapes/Circle#", document: "src/shapes.rs")
        #expect(context.declaration?.link == .implements(circle))
        #expect(context.underCaret == nil)
    }

    // MARK: - Fallback

    @Test func whitespaceAndKeywordsFallBackToTheOutline() async throws {
        let f = try await Self.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let context = ContextModel()
        context.update(Self.inputs(f, buffer: f.shapes, syntax: f.shapesSyntax, caret: f.shapes.byteOffset(line: 6, column: 39)))
        #expect(context.underCaret?.target.displayName == "Circle")
        // Blank line between the struct and the impl: no declaration, no symbol.
        context.update(Self.inputs(f, buffer: f.shapes, syntax: f.shapesSyntax, caret: f.shapes.byteOffset(line: 4, column: 0)))
        #expect(context.underCaret == nil)
        #expect(context.preview == .none)
        #expect(context.declaration == nil)
        #expect(context.declarationAbsence == .noDeclaration)
        // Indentation and the `let` keyword inside `area`: declaration stays, symbol clears.
        context.update(Self.inputs(f, buffer: f.shapes, syntax: f.shapesSyntax, caret: f.shapes.byteOffset(line: 8, column: 9)))
        #expect(context.underCaret == nil)
        #expect(context.declaration?.declaration.name == "area")
        // No parsed structure: the declaration region says so instead of guessing.
        context.update(Self.inputs(f, buffer: f.shapes, syntax: nil, caret: f.shapes.byteOffset(line: 8, column: 12)))
        #expect(context.declaration == nil)
        #expect(context.declarationAbsence == .noStructure)
        #expect(context.underCaret?.isLocal == true, "semantics do not depend on Tree-sitter")
    }

    @Test func localsAreQuietAndDescribedFromTheIndex() async throws {
        let f = try await Self.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let context = ContextModel()
        // The second `r` in `PI * r * r`.
        context.update(Self.inputs(f, buffer: f.shapes, syntax: f.shapesSyntax, caret: f.shapes.byteOffset(line: 9, column: 35)))
        let local = try #require(context.underCaret)
        #expect(local.isLocal && !local.isProminent)
        #expect(local.target.displayName == "r")
        #expect(local.localDefinitionLine == SnippetLine(number: 8, text: "        let r = self.radius;"))
        #expect(local.fileOccurrenceCount == 3)
        #expect(context.preview == .none, "locals get no async preview")
        #expect(context.previewQueryCount == 0)
    }

    @Test func externalSymbolsExplainMissingSourceWithoutFabricating() async throws {
        let f = try await Self.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let context = ContextModel()
        // `+=` is a core operator: known to the index, defined outside the repository.
        context.update(Self.inputs(f, buffer: f.lib, syntax: f.libSyntax, caret: f.lib.byteOffset(line: 8, column: 12)))
        let external = try #require(context.underCaret)
        #expect(external.isDefinedOutsideRepository)
        #expect(external.destination == nil)
        #expect(external.externalPackage?.hasPrefix("core") == true)
        guard case .unavailable(let message) = context.preview else {
            Issue.record("expected an unavailable preview, got \(context.preview)")
            return
        }
        #expect(message.contains("outside this repository"))
        #expect(context.previewQueryCount == 0)
    }

    // MARK: - Async safety

    @Test func staleAsyncResultsNeverRender() async throws {
        let f = try await Self.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let context = ContextModel()
        // Start a cross-file preview and a reference scan, then leave at once.
        context.update(Self.inputs(f, buffer: f.lib, syntax: f.libSyntax, caret: f.lib.byteOffset(line: 5, column: 28)))
        #expect(context.preview == .loading)
        #expect(context.references == .loading)
        context.update(Self.inputs(f, buffer: f.shapes, syntax: f.shapesSyntax, caret: f.shapes.byteOffset(line: 8, column: 9)))
        #expect(context.preview == .none)
        try await Self.waitUntil { Self.isLoaded(context.references) }
        try await Task.sleep(for: .milliseconds(150))
        #expect(context.preview == .none, "the abandoned Circle preview must not arrive")
        guard case .loaded(let results) = context.references else { return }
        #expect(results.displayName == "area", "the abandoned total_area scan must not arrive")
    }

    @Test func repositoryChangeAndResetDropEverything() async throws {
        let f = try await Self.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let context = ContextModel()
        context.update(Self.inputs(f, buffer: f.lib, syntax: f.libSyntax, caret: f.lib.byteOffset(line: 5, column: 28)))
        #expect(context.underCaret != nil && context.declaration != nil)
        context.reset()
        #expect(context.underCaret == nil && context.declaration == nil)
        #expect(context.references == .unavailable && context.preview == .none)
        try await Task.sleep(for: .milliseconds(150))
        #expect(context.preview == .none && context.references == .unavailable, "in-flight work was cancelled")

        // A different root resets cached results too: nothing is reused.
        context.update(Self.inputs(f, buffer: f.shapes, syntax: f.shapesSyntax, caret: f.shapes.byteOffset(line: 8, column: 12)))
        try await Self.waitUntil { Self.isLoaded(context.references) }
        let queries = context.referenceQueryCount
        let other = FileManager.default.temporaryDirectory.appending(path: "radiology-other-\(UUID().uuidString)")
        context.update(Self.inputs(f, buffer: f.shapes, syntax: f.shapesSyntax, caret: f.shapes.byteOffset(line: 8, column: 12), root: other))
        #expect(context.referenceQueryCount == queries + 1)
    }

    @Test func aNewIndexRevisionRefetchesTheSameDeclaration() async throws {
        let f = try await Self.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let context = ContextModel()
        let caret = f.shapes.byteOffset(line: 8, column: 12)
        context.update(Self.inputs(f, buffer: f.shapes, syntax: f.shapesSyntax, caret: caret))
        try await Self.waitUntil { Self.isLoaded(context.references) }
        let queries = context.referenceQueryCount
        context.update(Self.inputs(f, buffer: f.shapes, syntax: f.shapesSyntax, caret: caret, indexRevision: 2))
        #expect(context.referenceQueryCount == queries + 1)
        #expect(context.declarationBuildCount == 2)
    }

    @Test func newSourceBytesWithTheSameIndexInvalidateCachedExcerpts() async throws {
        let f = try await Self.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let context = ContextModel()
        // `impl Circle {`: Circle's definition is in this file, previewed from memory.
        let caret = f.shapes.byteOffset(line: 5, column: 6)
        context.update(Self.inputs(f, buffer: f.shapes, syntax: f.shapesSyntax, caret: caret))
        #expect(Self.loadedPreview(context.preview)?.lines.first?.text == "pub struct Circle {")
        try await Self.waitUntil { Self.isLoaded(context.references) }
        let queries = context.referenceQueryCount

        // Same index and revisions, new bytes on disk that still fit the index's coordinates.
        let edited = String(decoding: f.shapes.data, as: UTF8.self)
            .replacing("pub struct Circle {", with: "pub struct Circle { // edited")
        try Data(edited.utf8).write(to: f.root.appending(path: "src/shapes.rs"))
        let reloaded = try SourceBuffer(path: "src/shapes.rs", data: Data(edited.utf8))
        let syntax = try #require(try await SyntaxWorker().parse(reloaded))
        let movedCaret = reloaded.byteOffset(line: 5, column: 6)
        context.update(Self.inputs(f, buffer: reloaded, syntax: syntax, caret: movedCaret))
        #expect(Self.loadedPreview(context.preview)?.lines.first?.text == "pub struct Circle { // edited")
        #expect(context.referenceQueryCount == queries + 1, "references embed old snippets and must reload")
        try await Self.waitUntil { Self.isLoaded(context.references) }
        guard case .loaded(let results) = context.references else { return }
        let definition = results.groups.first { $0.path == "src/shapes.rs" }?.hits.first { $0.isDefinition }
        #expect(definition?.lineText == "pub struct Circle { // edited")

        // Unchanged bytes afterwards are stable again.
        context.update(Self.inputs(f, buffer: reloaded, syntax: syntax, caret: movedCaret + 1))
        #expect(context.referenceQueryCount == queries + 1)
    }

    @Test func explicitReferencesOverrideTheDeclarationUntilFollowCaret() async throws {
        let f = try await Self.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let context = ContextModel()
        let circleByte = f.lib.byteOffset(line: 5, column: 28)
        context.update(Self.inputs(f, buffer: f.lib, syntax: f.libSyntax, caret: circleByte))
        let target = try #require(context.underCaret?.target)
        context.showReferences(of: target)
        try await Self.waitUntil { Self.isLoaded(context.references) }
        guard case .loaded(let explicit) = context.references else { return }
        #expect(explicit.displayName == "Circle")
        // Moving the caret to another declaration does not replace explicit references.
        context.update(Self.inputs(f, buffer: f.shapes, syntax: f.shapesSyntax, caret: f.shapes.byteOffset(line: 8, column: 12)))
        #expect(context.declaration?.declaration.name == "area")
        guard case .loaded(let still) = context.references else { return }
        #expect(still.displayName == "Circle")
        context.followCaret()
        try await Self.waitUntil { Self.isLoaded(context.references) }
        guard case .loaded(let following) = context.references else { return }
        #expect(following.displayName == "area")
    }

    // MARK: - Unicode

    /// A synthetic UTF-16 index: emoji before an identifier on the same line,
    /// and a non-ASCII identifier. TextKit UTF-16 offsets convert to bytes
    /// once; every offset inside `café` is one identity, and an offset inside
    /// a surrogate pair never becomes a target.
    @Test func utf16CaretOffsetsResolveOneIdentityAcrossUnicode() async throws {
        let text = "fn café() -> u32 { 1 }\nfn main() {\n    let s = \"🚀🚀\"; let total = café();\n}\n"
        let buffer = try SourceBuffer(path: "src/uni.rs", data: Data(text.utf8))
        let line2 = "    let s = \"🚀🚀\"; let total = café();"
        func utf16Column(of needle: String, in line: String) -> Int {
            line.utf16.distance(from: line.utf16.startIndex, to: line.range(of: needle)!.lowerBound.samePosition(in: line.utf16)!)
        }
        let callColumn = utf16Column(of: "café()", in: line2)
        let totalColumn = utf16Column(of: "total", in: line2)
        let cafe = "rust-analyzer cargo uni 0.1.0 café()."
        var document = SCIPDocument()
        document.relativePath = "src/uni.rs"
        document.positionEncoding = 2
        document.occurrences = [
            SCIPOccurrence(range: SCIPRange(startLine: 0, startCharacter: 3, endLine: 0, endCharacter: 7), symbol: cafe, symbolRoles: SCIPSymbolRole.definition),
            SCIPOccurrence(range: SCIPRange(startLine: 2, startCharacter: totalColumn, endLine: 2, endCharacter: totalColumn + 5), symbol: "local 1", symbolRoles: SCIPSymbolRole.definition),
            SCIPOccurrence(range: SCIPRange(startLine: 2, startCharacter: callColumn, endLine: 2, endCharacter: callColumn + 4), symbol: cafe, symbolRoles: 0),
        ]
        var info = SCIPSymbolInformation()
        info.symbol = cafe
        info.displayName = "café"
        info.kind = 17
        info.signature = "fn café() -> u32"
        var local = SCIPSymbolInformation()
        local.symbol = "local 1"
        local.displayName = "total"
        local.kind = 61
        document.symbols = [info, local]
        var raw = SCIPIndex()
        raw.documents = [document]
        let index = SemanticIndex(indexes: [raw])
        let semantics = DocumentSemantics.make(document: try #require(index.documents["src/uni.rs"]), buffer: buffer)
        #expect(semantics.unmappedCount == 0)
        let syntax = try #require(try await SyntaxWorker().parse(buffer))
        let context = ContextModel()
        func moveTo(utf16 offset: Int) {
            context.update(ContextInputs(root: nil, buffer: buffer, sourceIdentity: SourceContentIdentity(buffer.data), syntax: syntax,
                                         caretByte: buffer.byteOffset(forUTF16: offset), index: index, indexRevision: 1,
                                         documentSemantics: semantics, documentRevision: 1))
        }
        let lineStart = buffer.utf16LineStarts[2]
        for offset in 0..<4 { moveTo(utf16: lineStart + callColumn + offset) }
        #expect(context.underCaret?.target.displayName == "café")
        #expect(context.underCaret?.signature == "fn café() -> u32")
        #expect(context.underCaretBuildCount == 1)
        #expect(context.declaration?.declaration.name == "main")
        // The same-file definition previews from memory, on the right line.
        #expect(Self.loadedPreview(context.preview)?.lines == [SnippetLine(number: 1, text: "fn café() -> u32 { 1 }")])
        // Between the halves of the first 🚀: clamps to the scalar, inside a string, no target.
        moveTo(utf16: lineStart + utf16Column(of: "🚀", in: line2) + 1)
        #expect(context.underCaret == nil)
        moveTo(utf16: lineStart + totalColumn + 2)
        #expect(context.underCaret?.target.displayName == "total")
        #expect(context.underCaret?.isLocal == true)
        // The byte range of the call maps back to exactly `café` in UTF-16.
        let call = try #require(semantics.occurrences.first { $0.symbol.symbol == cafe && !$0.isDefinition })
        #expect((buffer.text as NSString).substring(with: buffer.utf16Range(forByteRange: call.byteRange)) == "café")
    }

    @Test func referenceTextIsWindowedOnScalarBoundariesAndBounded() throws {
        let prefix = String(repeating: "é🚀x", count: 30_000)
        let line = "let v = \(prefix) target(1); // tail"
        let buffer = try SourceBuffer(path: "gen.rs", data: Data("fn a() {}\n\(line)\nfn b() {}\n".utf8))
        let start = buffer.lineStarts[1] + line.utf8.count - " target(1); // tail".utf8.count + 1
        let hit = SemanticQueryWorker.hit(in: buffer, range: start..<(start + 6), isDefinition: false)
        #expect(hit.match == "target")
        #expect(hit.leading.hasPrefix("…"))
        #expect(hit.leading.utf8.count <= SourceBuffer.displayLineLimit)
        #expect(hit.lineText.utf8.count <= SourceBuffer.displayLineLimit + "…".utf8.count)
        #expect(hit.context.allSatisfy { $0.text.utf8.count <= SourceBuffer.displayLineLimit + "…".utf8.count })
        #expect(hit.line == 2)
        let preview = DefinitionPreview.make(buffer: buffer, startByte: buffer.lineStarts[1], declarationEnd: nil, maxLines: 12)
        #expect(preview.lines.count == 2)
        #expect(preview.lines[0].text.utf8.count <= SourceBuffer.displayLineLimit + "…".utf8.count)
        #expect(!preview.lines[0].text.unicodeScalars.contains("\u{FFFD}"), "never split a scalar")
    }

    @Test func escapedImplDescriptorsAndURLVersionsReadCleanly() {
        let symbol = "rust-analyzer cargo core https://github.com/rust-lang/rust/library/core slice/impl#[`[T]`]first()."
        #expect(SCIPSymbolString.fallbackName(for: symbol) == "first")
        #expect(SCIPSymbolString.package(of: symbol) == "core")
        #expect(SCIPSymbolString.package(of: "rust-analyzer cargo serde_json 1.0.151 value/Value#") == "serde_json 1.0.151")
        #expect(SCIPSymbolString.package(of: "local 4") == nil)
    }

    @Test func nestedMultilineSignaturesStopAtTheBodyAndReadFlush() async throws {
        let text = "impl App {\n    #[inline]\n    fn open(\n        &self,\n        name: &str, // ✓ ünïcode\n    ) -> Result<(), E> {\n        body();\n    }\n}\n"
        let buffer = try SourceBuffer(path: "app.rs", data: Data(text.utf8))
        let syntax = try #require(try await SyntaxWorker().parse(buffer))
        let open = try #require(DeclarationContext.innermostDeclaration(at: buffer.byteOffset(line: 7, column: 9), in: syntax.symbols))
        #expect(open.name == "open")
        #expect(DeclarationContext.signature(of: open, buffer: buffer, folds: syntax.folds)
                == "fn open(\n    &self,\n    name: &str, // ✓ ünïcode\n) -> Result<(), E>")
        // Between the methods' closing brace and the impl's: the impl is innermost.
        #expect(DeclarationContext.innermostDeclaration(at: buffer.byteOffset(line: 8, column: 5), in: syntax.symbols)?.kind == "extension")
    }

    /// tkos `app_image.rs` shape: adjacent functions with no blank line. A
    /// cross-file preview must end with its own declaration, parsed off-main,
    /// not run into the next one.
    @Test func crossFilePreviewsEndAtTheirTreeSitterDeclaration() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "radiology-adjacent-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = """
        pub fn restore_base(image: Vec<u8>, host: &[u8]) -> Result<PreparedBase, Error> {
            restore(image, host, "base").map(PreparedBase)
        }
        pub fn restore_app(image: Vec<u8>, host: &[u8]) -> Result<PreparedApp, Error> {
            restore(image, host, "app").map(PreparedApp)
        }
        fn restore(image: Vec<u8>, host: &[u8], kind: &str) -> Result<Restored, Error> {
            let café = "🚀";
            Ok(Restored)
        }
        """
        try Data(source.utf8).write(to: root.appending(path: "app_image.rs"))
        let worker = SemanticQueryWorker()
        func preview(line: Int, column: Int, length: Int) async throws -> DefinitionPreview? {
            try await worker.definitionPreview(at: SemanticPosition(path: "app_image.rs",
                                                                    range: SCIPRange(startLine: line, startCharacter: column, endLine: line, endCharacter: column + length),
                                                                    encoding: .utf8),
                                               root: root, maxLines: DefinitionPreview.maxLines)
        }
        let app = try #require(try await preview(line: 3, column: 7, length: 11))
        #expect(app.lines.map(\.number) == [4, 5, 6])
        #expect(app.lines.last?.text == "}")
        #expect(!app.lines.contains { $0.text.contains("fn restore(") })
        #expect(!app.isTruncated)
        // A second symbol in the same file reuses the parsed structure.
        let restore = try #require(try await preview(line: 6, column: 3, length: 7))
        #expect(restore.lines.map(\.number) == [7, 8, 9, 10])
        // A file without a grammar keeps the blank-line bound.
        try Data("one\ntwo\n\nthree\n".utf8).write(to: root.appending(path: "notes.txt"))
        let plain = try #require(try await worker.definitionPreview(
            at: SemanticPosition(path: "notes.txt", range: SCIPRange(startLine: 0, startCharacter: 0, endLine: 0, endCharacter: 3), encoding: .utf8),
            root: root, maxLines: DefinitionPreview.maxLines))
        #expect(plain.lines.map(\.text) == ["one", "two"])
    }

    /// Partial, stale, and reindexing states with a usable index classify by
    /// file coverage; only an empty index is "no semantic index".
    @Test func availabilityDistinguishesRepositoryIndexFromFileCoverage() throws {
        let (_, index) = try SemanticIndexTests.loadFixture()
        let progress = IndexingProgress(phase: .indexing, strategy: nil, step: 1, total: 1, message: "Running rust-analyzer…")
        for status in [SemanticIndexStatus.current, .partial(reason: "2 files missing"), .possiblyStale(reason: "HEAD moved"),
                       .indexing(progress)] {
            #expect(SemanticAvailability.resolve(status: status, index: index, path: "README.md", mappedPath: nil) == .fileNotIndexed)
            #expect(SemanticAvailability.resolve(status: status, index: index, path: "src/lib.rs", mappedPath: nil) == .mapping)
            #expect(SemanticAvailability.resolve(status: status, index: index, path: "src/lib.rs", mappedPath: "src/lib.rs") == .available)
        }
        #expect(SemanticAvailability.resolve(status: .indexing(progress), index: .empty, path: "README.md", mappedPath: nil)
                == .indexing(message: "Running rust-analyzer…"))
        #expect(SemanticAvailability.resolve(status: .noIndex(reason: "No supported projects."), index: .empty, path: "a.rs", mappedPath: nil)
                == .repositoryNotIndexed(reason: "No supported projects."))
        #expect(SemanticAvailability.fileNotIndexed.headerDetail == "File not indexed")
        #expect(SemanticAvailability.repositoryNotIndexed(reason: "x").headerDetail == "No semantic index")
        #expect(SemanticAvailability.available.explanation == nil)
    }

    /// Concise default: everything starts collapsed, an expansion survives
    /// caret movement within its identity, and collapses on a new identity.
    /// The two regions' expansions are independent.
    @Test func expansionBelongsToIdentityAndStartsCollapsed() async throws {
        let f = try await Self.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let context = ContextModel()
        // `radius` in `let r = self.radius;` spans columns 21..<27.
        let radius = f.shapes.byteOffset(line: 8, column: 22)
        context.update(Self.inputs(f, buffer: f.shapes, syntax: f.shapesSyntax, caret: radius))
        #expect(context.underCaret?.target.displayName == "radius")
        try await Self.waitUntil { Self.isLoaded(context.references) }
        #expect(!context.isDeclarationExpanded && !context.isDefinitionExpanded && context.expandedReferenceIDs.isEmpty)
        guard case .loaded(let results) = context.references else { return }
        let call = try #require(results.groups.first { $0.path == "src/lib.rs" }?.hits.first)

        context.isDeclarationExpanded = true
        context.isDefinitionExpanded = true
        context.toggleReference(call.id)
        context.setReference("src/nowhere.rs:0", expanded: true)
        #expect(context.expandedReferenceIDs == [call.id], "unknown rows are ignored")

        // Within the same `radius` occurrence: nothing collapses.
        context.update(Self.inputs(f, buffer: f.shapes, syntax: f.shapesSyntax, caret: radius + 3))
        #expect(context.isDeclarationExpanded && context.isDefinitionExpanded && context.isReferenceExpanded(call.id))

        // New under-caret identity (`self`), same declaration: only the definition collapses.
        context.update(Self.inputs(f, buffer: f.shapes, syntax: f.shapesSyntax, caret: f.shapes.byteOffset(line: 8, column: 18)))
        #expect(!context.isDefinitionExpanded)
        #expect(context.isDeclarationExpanded && context.isReferenceExpanded(call.id))

        // New declaration (`new`): declaration and reference rows collapse.
        context.isDefinitionExpanded = true
        context.update(Self.inputs(f, buffer: f.shapes, syntax: f.shapesSyntax, caret: f.shapes.byteOffset(line: 6, column: 40)))
        #expect(!context.isDeclarationExpanded && context.expandedReferenceIDs.isEmpty)
        #expect(!context.isDefinitionExpanded, "`radius` is a new identity too")

        // Collapsing is the reverse toggle, and reset clears everything.
        try await Self.waitUntil { Self.isLoaded(context.references) }
        guard case .loaded(let newResults) = context.references, let first = newResults.groups.first?.hits.first else { return }
        context.toggleReference(first.id)
        context.toggleReference(first.id)
        #expect(context.expandedReferenceIDs.isEmpty)
        context.toggleReference(first.id)
        context.isDeclarationExpanded = true
        context.reset()
        #expect(!context.isDeclarationExpanded && context.expandedReferenceIDs.isEmpty)
    }
}
