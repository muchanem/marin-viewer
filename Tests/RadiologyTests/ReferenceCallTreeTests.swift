import Foundation
import Testing
@testable import Radiology

struct ReferenceCallTreeTests {
    /// Index tokens by their exact UTF-16 columns, including non-ASCII names.
    /// Definitions and calls are deliberately spread over separate files.
    static func fixture() throws -> (URL, SemanticIndex, ReferenceHit) {
        let root = FileManager.default.temporaryDirectory.appending(path: "radiology-callers-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let texts = [
            "leaf.rs": "fn café() {}\nfn middle() { let s = \"🚀\"; café(); }\n",
            "entry.rs": "fn left() { middle(); }\nfn right() { middle(); }\nfn entry() { left(); right(); }\n",
            "boundary.rs": "fn callbacks() { let f = middle; let c = || middle(); }\nfn nested() { fn inner() { middle(); } inner(); }\n"
        ]
        let names = ["café", "middle", "left", "right", "entry", "callbacks", "nested", "inner"]
        var raw = SCIPIndex()
        for path in texts.keys.sorted() {
            let text = try #require(texts[path])
            try Data(text.utf8).write(to: root.appending(path: path))
            var document = SCIPDocument()
            document.relativePath = path
            document.positionEncoding = 2
            for (lineIndex, line) in text.split(separator: "\n").enumerated() {
                for name in names {
                    var search = line.startIndex..<line.endIndex
                    while let range = line.range(of: name, range: search) {
                        let column = line[..<range.lowerBound].utf16.count
                        let isDefinition = line[..<range.lowerBound].hasSuffix("fn ")
                        document.occurrences.append(SCIPOccurrence(
                            range: SCIPRange(startLine: lineIndex, startCharacter: column, endLine: lineIndex, endCharacter: column + name.utf16.count),
                            symbol: "test cargo fixture 1 \(name)().", symbolRoles: isDefinition ? SCIPSymbolRole.definition : 0))
                        search = range.upperBound..<line.endIndex
                    }
                }
            }
            raw.documents.append(document)
        }
        let index = SemanticIndex(indexes: [raw])
        let buffer = try SourceBuffer(path: "leaf.rs", data: Data(try #require(texts["leaf.rs"]).utf8))
        let byte = try #require(buffer.text.range(of: "café();").map { buffer.text[..<$0.lowerBound].utf8.count })
        let hit = SemanticQueryWorker.hit(in: buffer, range: byte..<(byte + "café".utf8.count), isDefinition: false)
        return (root, index, hit)
    }

    @Test func tracesEveryBranchAndStopsAtHonestBoundaries() async throws {
        let (root, index, hit) = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = try await ReferenceCallTreeWorker().trace(hit, index: index, root: root)
        #expect(tree.callers.map(\.name) == ["middle", "callbacks", "Closure in callbacks", "inner", "nested", "left", "entry", "right", "entry"])
        #expect(tree.callers.map(\.depth) == [0, 1, 1, 1, 2, 1, 2, 1, 2])
        #expect(tree.callers[1].note == "Non-call reference; invocation unknown")
        #expect(tree.callers[2].note == "Closure invocation is not indexed")
        #expect(tree.callers[4].note == "No indexed callers")
        #expect(tree.callers[5].location.path == "entry.rs")
        #expect(tree.callers[6].line == 3)
        #expect(tree.notices.isEmpty && !tree.hasMore)
        #expect(hit.match == "café")
    }

    @Test func recursionAndContinuationPreservePaths() async throws {
        let (root, index, hit) = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let worker = ReferenceCallTreeWorker()
        let short = try await worker.trace(hit, index: index, root: root, budget: 3)
        #expect(short.callers.count == 3 && short.hasMore)
        let all = try await worker.trace(hit, index: index, root: root, budget: 259)
        #expect(Array(all.callers.prefix(3)) == short.callers)
        #expect(!all.hasMore)

        // A self-call terminates only this branch; sibling entry paths remain.
        let text = "fn middle() { middle(); }\nfn entry() { middle(); }\n"
        try Data(text.utf8).write(to: root.appending(path: "cycle.rs"))
        var document = SCIPDocument()
        document.relativePath = "cycle.rs"
        let middle = "test cargo cycle 1 middle()."
        let entry = "test cargo cycle 1 entry()."
        document.occurrences = [
            SCIPOccurrence(range: SCIPRange(startLine: 0, startCharacter: 3, endLine: 0, endCharacter: 9), symbol: middle, symbolRoles: SCIPSymbolRole.definition),
            SCIPOccurrence(range: SCIPRange(startLine: 0, startCharacter: 14, endLine: 0, endCharacter: 20), symbol: middle, symbolRoles: 0),
            SCIPOccurrence(range: SCIPRange(startLine: 1, startCharacter: 3, endLine: 1, endCharacter: 8), symbol: entry, symbolRoles: SCIPSymbolRole.definition),
            SCIPOccurrence(range: SCIPRange(startLine: 1, startCharacter: 13, endLine: 1, endCharacter: 19), symbol: middle, symbolRoles: 0)
        ]
        var raw = SCIPIndex()
        raw.documents = [document]
        let buffer = try SourceBuffer(path: "cycle.rs", data: Data(text.utf8))
        let definition = SemanticQueryWorker.hit(in: buffer, range: 3..<9, isDefinition: true)
        let cycle = try await worker.trace(definition, index: SemanticIndex(indexes: [raw]), root: root)
        #expect(cycle.callers.map(\.name) == ["middle", "entry"])
        #expect(cycle.callers[0].note == "Recursive branch stopped")
        #expect(cycle.callers[1].note == "No indexed callers")
    }

    @Test func missingFilesStaleCoordinatesAndCancellationAreExplicit() async throws {
        let (root, index, hit) = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appending(path: "entry.rs"))
        try Data("fn callbacks() {}\n".utf8).write(to: root.appending(path: "boundary.rs"))
        let worker = ReferenceCallTreeWorker()
        let tree = try await worker.trace(hit, index: index, root: root)
        #expect(tree.notices.contains("entry.rs: file could not be read"))
        #expect(tree.notices.contains("boundary.rs: stale index coordinates"))
        let task = Task { try await worker.trace(hit, index: index, root: root) }
        task.cancel()
        do { _ = try await task.value; Issue.record("cancelled trace completed") }
        catch is CancellationError { }
    }

    @Test func launchAppearsOnceInAMutuallyRecursiveChain() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "radiology-launch-cycle-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lines = ["fn leaf() {}", "fn launch() { leaf(); relay(); }", "fn relay() { launch(); }", "fn entry() { relay(); }", "fn other() { launch(); }"]
        let names = ["leaf", "launch", "relay", "entry", "other"]
        var document = SCIPDocument()
        document.relativePath = "launch.rs"
        for (lineIndex, line) in lines.enumerated() {
            for name in names {
                guard let range = line.range(of: name) else { continue }
                let column = line[..<range.lowerBound].utf8.count
                document.occurrences.append(SCIPOccurrence(
                    range: SCIPRange(startLine: lineIndex, startCharacter: column, endLine: lineIndex, endCharacter: column + name.utf8.count),
                    symbol: "test cargo mutual 1 \(name)().", symbolRoles: line[..<range.lowerBound].hasSuffix("fn ") ? SCIPSymbolRole.definition : 0))
            }
        }
        let data = Data(lines.joined(separator: "\n").utf8)
        try data.write(to: root.appending(path: document.relativePath))
        var raw = SCIPIndex()
        raw.documents = [document]
        let index = SemanticIndex(indexes: [raw])
        let buffer = try SourceBuffer(path: document.relativePath, data: data)
        let hit = SemanticQueryWorker.hit(in: buffer, range: 3..<7, isDefinition: true)
        let worker = ReferenceCallTreeWorker()
        let tree = try await worker.trace(hit, index: index, root: root)
        #expect(tree.callers.map(\.name) == ["leaf", "launch", "relay", "entry", "other"])
        #expect(tree.callers.map(\.depth) == [0, 1, 2, 3, 2])
        #expect(tree.callers[2].note == "Recursive branch stopped")
        // The sibling branch and continuation remain available after cutting
        // launch -> relay -> launch before the duplicate launch row.
        let prefix = try await worker.trace(hit, index: index, root: root, budget: 3)
        #expect(prefix.hasMore)
        #expect(prefix.callers == Array(tree.callers.prefix(3)))
        var path: [SemanticSymbolID] = []
        for caller in tree.callers {
            path = Array(path.prefix(caller.depth))
            if let symbol = caller.symbol {
                #expect(!path.contains(symbol), "each root-to-leaf chain must have unique callable identities")
                path.append(symbol)
            }
        }
    }

    @Test func distinctFunctionsNamedLaunchAreNotMistakenForACycle() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "radiology-distinct-launch-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = "test cargo distinct 1 first/launch()."
        let second = "test cargo distinct 1 second/launch()."
        let entry = "test cargo distinct 1 entry()."
        let examples: [(String, String, String, String?, String?)] = [
            ("first.rs", "fn launch() {}", first, nil, nil),
            ("second.rs", "fn launch() { first(); }", second, "first", first),
            ("entry.rs", "fn entry() { second(); }", entry, "second", second)
        ]
        var raw = SCIPIndex()
        for (path, text, definition, callName, callee) in examples {
            try Data(text.utf8).write(to: root.appending(path: path))
            var document = SCIPDocument()
            document.relativePath = path
            let name = path == "entry.rs" ? "entry" : "launch"
            document.occurrences = [SCIPOccurrence(
                range: SCIPRange(startLine: 0, startCharacter: 3, endLine: 0, endCharacter: 3 + name.utf8.count),
                symbol: definition, symbolRoles: SCIPSymbolRole.definition)]
            if let callName, let callee, let range = text.range(of: callName + "()") {
                let start = text[..<range.lowerBound].utf8.count
                document.occurrences.append(SCIPOccurrence(
                    range: SCIPRange(startLine: 0, startCharacter: start, endLine: 0, endCharacter: start + callName.utf8.count),
                    symbol: callee, symbolRoles: 0))
            }
            raw.documents.append(document)
        }
        let buffer = try SourceBuffer(path: "first.rs", data: Data("fn launch() {}".utf8))
        let hit = SemanticQueryWorker.hit(in: buffer, range: 3..<9, isDefinition: true)
        let tree = try await ReferenceCallTreeWorker().trace(hit, index: SemanticIndex(indexes: [raw]), root: root)
        #expect(tree.callers.map(\.name) == ["launch", "launch", "entry"])
        #expect(tree.callers[0].symbol != tree.callers[1].symbol)
        #expect(tree.callers.map { $0.location.path } == ["first.rs", "second.rs", "entry.rs"])
        #expect(!tree.callers.contains { $0.note == "Recursive branch stopped" })
    }

    @Test func deepTreesHaveNoDepthCutoffAndCanContinuePastTheInitialBudget() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "radiology-deep-callers-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var document = SCIPDocument()
        document.relativePath = "deep.rs"
        var lines: [String] = []
        for level in 0..<270 {
            let name = "f\(level)"
            let body = level == 0 ? "" : "f\(level - 1)();"
            lines.append("fn \(name)() { \(body) }")
            document.occurrences.append(SCIPOccurrence(
                range: SCIPRange(startLine: level, startCharacter: 3, endLine: level, endCharacter: 3 + name.utf8.count),
                symbol: "test cargo deep 1 \(name)().", symbolRoles: SCIPSymbolRole.definition))
            if level > 0 {
                let start = 3 + name.utf8.count + 5
                document.occurrences.append(SCIPOccurrence(
                    range: SCIPRange(startLine: level, startCharacter: start, endLine: level, endCharacter: start + "f\(level - 1)".utf8.count),
                    symbol: "test cargo deep 1 f\(level - 1)().", symbolRoles: 0))
            }
        }
        let data = Data(lines.joined(separator: "\n").utf8)
        try data.write(to: root.appending(path: document.relativePath))
        let buffer = try SourceBuffer(path: document.relativePath, data: data)
        let hit = SemanticQueryWorker.hit(in: buffer, range: 3..<5, isDefinition: true)
        var raw = SCIPIndex()
        raw.documents = [document]
        let index = SemanticIndex(indexes: [raw])
        let worker = ReferenceCallTreeWorker()
        let first = try await worker.trace(hit, index: index, root: root)
        #expect(first.callers.count == 256 && first.hasMore)
        #expect(first.callers.last?.depth == 255)
        let all = try await worker.trace(hit, index: index, root: root, budget: 512)
        #expect(all.callers.count == 270 && !all.hasMore)
        #expect(all.callers.last?.depth == 269)
        #expect(all.callers.last?.name == "f269")
    }

    @MainActor @Test func disclosureLoadsLazilyAndResetDiscardsWork() async throws {
        let f = try await ContextModelTests.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let model = ContextModel()
        let semantics = DocumentSemantics.make(document: try #require(f.index.documents[f.shapes.path]), buffer: f.shapes)
        model.update(ContextInputs(root: f.root, buffer: f.shapes, sourceIdentity: SourceContentIdentity(f.shapes.data), syntax: f.shapesSyntax,
                                   caretByte: f.shapes.byteOffset(line: 8, column: 12), index: f.index, indexRevision: 1,
                                   documentSemantics: semantics, documentRevision: 1))
        try await ContextModelTests.waitUntil { if case .loaded = model.references { true } else { false } }
        #expect(model.referenceCallTrees.isEmpty)
        guard case .loaded(let results) = model.references else { return }
        let hit = try #require(results.groups.first { $0.path == "src/lib.rs" }?.hits.first)
        model.setReference(hit.id, expanded: true)
        try await ContextModelTests.waitUntil { if case .loaded = model.referenceCallTrees[hit.id] { true } else { false } }
        guard case .loaded(let tree) = model.referenceCallTrees[hit.id] else { return }
        #expect(tree.callers.first?.name == "total_area")
        model.setReference(hit.id, expanded: false)
        model.setReference(hit.id, expanded: true)
        #expect(model.referenceCallTrees[hit.id] == .loaded(tree))
        model.update(ContextModelTests.inputs(f, buffer: f.shapes, syntax: f.shapesSyntax,
                                              caret: f.shapes.byteOffset(line: 8, column: 12), indexRevision: 2))
        try await ContextModelTests.waitUntil { if case .loaded = model.references { true } else { false } }
        model.setReference(hit.id, expanded: true)
        #expect(model.referenceCallTrees[hit.id] == .loading)
        model.reset()
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.referenceCallTrees.isEmpty && model.expandedReferenceIDs.isEmpty)
    }
}
