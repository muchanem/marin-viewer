import Foundation
import Testing
@testable import Radiology

struct SyntaxWorkerTests {
    @Test func rustSymbolsPreserveActualContainmentAndDeclarationOrder() async throws {
        let source = """
        struct PreparedApp(Restored);
        impl PreparedApp {
            pub fn image(self) -> Restored { self.0 }
        }
        struct SnapshotBootstrapGlobals(Vec<u8>);
        impl SnapshotBootstrapGlobals {
            fn hide() { println!(\"hide\"); }
            fn restore() { println!(\"restore\"); }
        }
        pub fn create() { println!(\"create\"); }
        pub fn restore_base() { println!(\"base\"); }
        pub fn restore_app() { println!(\"app\"); }
        """
        let snapshot = try #require(try await SyntaxWorker().parse(
            SourceBuffer(path: "app_image.rs", data: Data(source.utf8))))
        let roots = DocumentSymbol.roots(in: snapshot.symbols)
        #expect(roots.map(\.name) == ["PreparedApp", "PreparedApp", "SnapshotBootstrapGlobals",
                                      "SnapshotBootstrapGlobals", "create", "restore_base", "restore_app"])
        let preparedImpl = try #require(roots.first { $0.name == "PreparedApp" && $0.kind == "extension" })
        #expect(preparedImpl.children(in: snapshot.symbols).map(\.name) == ["image"])
        let globalsImpl = try #require(roots.first { $0.name == "SnapshotBootstrapGlobals" && $0.kind == "extension" })
        #expect(globalsImpl.children(in: snapshot.symbols).map(\.name) == ["hide", "restore"])
    }
    @Test func swiftQueriesProduceByteBasedHighlightsSymbolsScopesAndFolds() async throws {
        let text = """
        // 🩻 Unicode before declarations exercises UTF-8 byte coordinates.
        struct Scan {
            let title = "胸部"

            func render(value: Int) -> String {
                if value > 0 {
                    return title
                }
                return "none"
            }
        }
        """
        let buffer = try SourceBuffer(path: "Scan.swift", data: Data(text.utf8))
        let snapshot = try #require(try await SyntaxWorker().parse(buffer))

        #expect(snapshot.path == "Scan.swift")
        #expect(snapshot.languageID == "swift")
        #expect(snapshot.languageName == "Swift")
        #expect(snapshot.highlight(named: "keyword.type", text: "struct", in: buffer))
        #expect(snapshot.highlight(named: "function", text: "render", in: buffer))
        #expect(snapshot.symbol("type", "Scan"))
        #expect(snapshot.symbol("function", "render"))
        #expect(snapshot.scopes.contains { $0.kind == "function" })
        #expect(snapshot.folds.contains { $0.kind == "function" })
        #expect(snapshot.folds.contains { $0.kind == "type" })
        for range in snapshot.highlights.map(\.byteRange) + snapshot.folds.map(\.byteRange) {
            #expect(range.lowerBound >= 0 && range.upperBound <= buffer.data.count)
            let utf16 = buffer.utf16Range(forByteRange: range)
            #expect(utf16.location >= 0 && NSMaxRange(utf16) <= buffer.utf16Count)
        }
    }

    @Test func swiftFixtureKeepsItsFullDeclarationStructure() async throws {
        let (_, snapshot) = try await SyntaxFixtures.snapshot("sample.swift")
        #expect(snapshot.languageID == "swift")
        #expect(!snapshot.hasParseErrors)
        #expect(snapshot.symbol("protocol", "Renderer"))
        #expect(snapshot.symbol("type", "Scan"))
        #expect(snapshot.symbol("typealias", "Titles"))
        #expect(snapshot.symbol("initializer", "init"))
        #expect(snapshot.symbol("deinitializer", "deinit"))
    }

    /// Every capture a grammar returns must stay inside the buffer and survive
    /// the single UTF-16 conversion TextKit needs, including past astral and
    /// multi-byte characters.
    @Test(arguments: SyntaxFixtures.names)
    func everyCaptureStaysInsideCanonicalUTF8ByteRanges(name: String) async throws {
        let (buffer, snapshot) = try await SyntaxFixtures.snapshot(name)
        let ranges = snapshot.highlights.map(\.byteRange) + snapshot.folds.map(\.byteRange)
            + snapshot.scopes.map(\.byteRange) + snapshot.symbols.map(\.byteRange)
            + snapshot.symbols.map(\.selectionByteRange)
        #expect(!ranges.isEmpty)
        for range in ranges {
            #expect(range.lowerBound >= 0)
            #expect(range.upperBound <= buffer.data.count)
            #expect(range.lowerBound <= range.upperBound)
            let utf16 = buffer.utf16Range(forByteRange: range)
            #expect(utf16.location >= 0)
            #expect(NSMaxRange(utf16) <= buffer.utf16Count)
        }
        // Every fixture embeds 胸部 or 放射線. Those bytes must survive the
        // round trip through the TextKit boundary at their exact location.
        let marker = buffer.data.range(of: Data("胸部".utf8)) ?? buffer.data.range(of: Data("放射線".utf8))
        let markerRange = try #require(marker, "\(name) should contain multi-byte text")
        let utf16Marker = buffer.utf16Range(forByteRange: markerRange)
        #expect((buffer.text as NSString).substring(with: utf16Marker) == buffer.text(in: markerRange))
        #expect(buffer.byteOffset(forUTF16: utf16Marker.location) == markerRange.lowerBound)
    }

    @Test func astralCharactersDoNotShiftCaptureRanges() async throws {
        let text = "// 🩻🩻 emoji\nlet title = \"胸部\"\nfunc scan() -> String { title }\n"
        let buffer = try SourceBuffer(path: "Astral.swift", data: Data(text.utf8))
        let snapshot = try #require(try await SyntaxWorker().parse(buffer))
        let comment = try #require(snapshot.highlights.first { $0.name == "comment" })
        #expect(buffer.text(in: comment.byteRange).hasPrefix("// 🩻🩻"))
        let function = try #require(snapshot.highlights.first { $0.name == "function" })
        let utf16 = buffer.utf16Range(forByteRange: function.byteRange)
        let nsText = buffer.text as NSString
        #expect(nsText.substring(with: utf16) == "scan")
    }

    @Test func cfgGatedFunctionLocalOccurrencesIncludeShadowingButExcludeTextAndOtherFunctions() async throws {
        let text = """
        #[cfg(target_os = \"android\")]
        fn android_log(message: &str) {
            let message = CString::new(message).unwrap_or(\"message\");
            unsafe { write(message); } // message
        }
        fn unrelated(message: &str) { use_it(message); }
        """
        let buffer = try SourceBuffer(path: "app_image.rs", data: Data(text.utf8))
        let snapshot = try #require(try await SyntaxWorker().parse(buffer))
        let clicked = try #require(buffer.data.range(of: Data("let message".utf8)))
        let selection = try #require(snapshot.localIdentifierSelection(at: clicked.lowerBound + 5, in: buffer))
        #expect(selection.byteRanges.count == 4, "parameter, shadowing local, initializer reference, and call argument")
        #expect(selection.byteRanges.allSatisfy { buffer.text(in: $0) == "message" })
        let function = try #require(snapshot.scopes.first { $0.kind == "function" && $0.byteRange.contains(clicked.lowerBound) })
        #expect(selection.byteRanges.allSatisfy(function.byteRange.contains))
        #expect(!selection.byteRanges.contains { range in
            snapshot.highlights.contains { ($0.name.hasPrefix("string") || $0.name.hasPrefix("comment")) && $0.byteRange.overlaps(range) }
        })
    }

    @Test func unsupportedFilesGracefullyRemainPlainText() async throws {
        let buffer = try SourceBuffer(path: "README.md", data: Data("# Read me".utf8))
        #expect(try await SyntaxWorker().parse(buffer) == nil)
    }

    /// Broken source must still read, and should still give back whatever
    /// structure the grammar managed to recover.
    @Test(arguments: [
        ("Broken.swift", "struct Broken { func run( { return 1 }"),
        ("broken.rs", "fn main( { let x = ; }"),
        ("broken.go", "package main\nfunc main( { x := }"),
        ("broken.py", "def broken(:\n    return ["),
        ("broken.js", "function broken( { const x = ; }"),
        ("broken.jsx", "const A = () => <div className=;"),
        ("broken.ts", "interface Broken { name: ; }\nfunction f( {"),
        ("broken.tsx", "const A: FC = () => <div className=;"),
        ("broken.kt", "fun broken( { val x = }"),
        ("broken.kts", "val x = ; class {"),
    ])
    func malformedSourceStillReturnsPartialStructure(name: String, text: String) async throws {
        let buffer = try SourceBuffer(path: name, data: Data(text.utf8))
        let snapshot = try #require(try await SyntaxWorker().parse(buffer))
        #expect(snapshot.hasParseErrors, "\(name) should report a parse error")
        #expect(!snapshot.highlights.isEmpty, "\(name) should still recover some highlights")
        #expect(buffer.text == text, "the source itself must stay intact and readable")
        for range in snapshot.highlights.map(\.byteRange) {
            #expect(range.upperBound <= buffer.data.count)
        }
    }

    @Test func emptyAndWhitespaceOnlySourcesAreHandled() async throws {
        for name in ["Empty.swift", "empty.rs", "empty.py", "empty.tsx", "empty.kt"] {
            let buffer = try SourceBuffer(path: name, data: Data("\n".utf8))
            let snapshot = try #require(try await SyntaxWorker().parse(buffer))
            #expect(snapshot.symbols.isEmpty)
            #expect(snapshot.folds.isEmpty)
        }
    }
}
