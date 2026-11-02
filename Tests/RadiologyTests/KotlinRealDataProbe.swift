import Foundation
import Testing
@testable import Radiology

/// Opt-in read-only validation of the compiler output for the user's exact
/// PR #758 example. Compilation happens separately in an isolated workspace.
struct KotlinRealDataProbe {
    /// Uses the actual repository listing, workspace copier, installed adapter,
    /// Gradle runner, source verification and cache publication. No manual copy
    /// bypasses the application path. The pinned head tree is read-only.
    @Test @MainActor func actualPR758IndexesThroughTheApplicationService() async throws {
        guard ProcessInfo.processInfo.environment["RADIOLOGY_REAL_KOTLIN_SERVICE_PROBE"] == "1" else { return }
        let root = URL(filePath: ProcessInfo.processInfo.environment["RADIOLOGY_KOTLIN_SERVICE_ROOT"]
            ?? "/Users/tqbf/Library/Caches/Radiology/repositories/98b359c61dd73dfb/revisions/5d2ffdd2976c62a220118e30780edfe8fb6f2120/tree")
        let snapshot = try await RepositoryWorker().open(root)
        let listing = try await CommandRunner().run(GitFixture.git, arguments: ["ls-tree", "-r", "-z", "HEAD"], directory: snapshot.root)
        var ids: [String: String] = [:]
        for entry in listing.split(separator: 0) {
            let text = String(decoding: entry, as: UTF8.self)
            guard let tab = text.firstIndex(of: "\t"), let id = text[..<tab].split(separator: " ").last else { continue }
            ids[String(text[text.index(after: tab)...])] = String(id)
        }
        let cacheRoot = FileManager.default.temporaryDirectory.appending(path: "radiology-kotlin-service-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        let cache = IndexCache(root: cacheRoot, flat: true)
        let service = SemanticIndexService(indexers: [ScipKotlinIndexer()], cache: cache)
        let sink = PublicationSink()
        await service.open(snapshot, options: IndexOpenOptions(cache: cache,
            revision: "5d2ffdd2976c62a220118e30780edfe8fb6f2120", blobIDs: ids)) { await sink.receive($0) }
        try await IndexingTests.waitUntil(.seconds(900)) {
            guard let status = sink.latest?.status else { return false }
            switch status { case .current, .partial, .failed: return true; default: return false }
        }
        let publication = try #require(sink.latest)
        let outcome = try #require(publication.outcomes.first)
        if case .failed(let failure) = outcome.result {
            print("Kotlin service failure: \(failure.message)\n\(failure.stderr)\n\(failure.stdout)")
        }
        #expect(outcome.result == .generated)
        let path = "modules/contacts/src/main/java/inc/tk/os/modules/ContactsModule.kt"
        let document = try #require(publication.index.documents[path])
        let buffer = try await SourceStore().load(root: snapshot.root, path: path)
        let mapped = DocumentSemantics.make(document: document, buffer: buffer)
        let line = buffer.displayLineText(141)
        let start = try #require(line.range(of: "addSecrecyTag")).lowerBound
        let byte = buffer.byteOffset(line: 141) + line[..<start].utf8.count + 3
        let target = try #require(publication.index.target(in: mapped, at: byte))
        #expect(target.displayName == "addSecrecyTag")
        #expect(target.definitions.first?.path == "core/src/main/kotlin/inc/tk/os/module/SecrecyCtx.kt")
        let references = try await SemanticQueryWorker().references(of: target.symbol, in: publication.index, root: snapshot.root)
        #expect(references.referenceCount > 0 && references.unmappedCount == 0 && references.unreadablePaths.isEmpty)
        #expect(publication.index.documents.keys.allSatisfy(Set(snapshot.files.map(\.path)).contains))
        let metadata = try #require(cache.loadMetadata(for: snapshot.root))
        #expect(metadata.strategies.first?.capability == outcome.capability)
        #expect(metadata.strategies.first?.documentCount == publication.index.documentCount)
        let files = try FileManager.default.contentsOfDirectory(at: cacheRoot, includingPropertiesForKeys: nil)
        #expect(!files.contains { $0.lastPathComponent.hasPrefix("build-inputs-") }, "workspace removed after service completion")
        print("Kotlin service PR758: \(publication.index.documentCount) published source documents, \(references.referenceCount) references in \(references.fileCount) files, \(outcome.capability), cache verified")
        await service.close()
    }

    @Test func contactsCaretResolvesRealKotlinDefinitionAndReferences() async throws {
        guard ProcessInfo.processInfo.environment["RADIOLOGY_REAL_KOTLIN_PROBE"] == "1" else { return }
        let root = URL(filePath: ProcessInfo.processInfo.environment["RADIOLOGY_KOTLIN_SOURCE_ROOT"] ?? "/private/tmp/radiology-kotlin-pr758")
        let path = "modules/contacts/src/main/java/inc/tk/os/modules/ContactsModule.kt"
        let raw = try SCIPDecoder.decode(Data(contentsOf: URL(filePath:
            ProcessInfo.processInfo.environment["RADIOLOGY_KOTLIN_INDEX"] ?? "/tmp/radiology-pr758-kotlin.scip")))
        let index = SemanticIndex(inputs: [.init(index: raw, defaultEncoding: ScipKotlinIndexer().defaultEncoding)])
        let buffer = try SourceBuffer(path: path, data: Data(contentsOf: root.appending(path: path)))
        let document = try #require(index.documents[path], "the compiler must actually emit ContactsModule.kt")
        let semantics = DocumentSemantics.make(document: document, buffer: buffer)
        let unmapped = document.occurrences.filter { buffer.byteRange(for: $0.range, encoding: document.encoding) == nil }
        #expect(unmapped.allSatisfy { $0.roles & SCIPSymbolRole.definition != 0 && $0.symbol.symbol.contains("`<init>`") },
                "the known generated-constructor range bug must not conceal unmapped ordinary source tokens")
        let line = buffer.displayLineText(141)
        let column = try #require(line.range(of: "addSecrecyTag")).lowerBound
        let byte = buffer.byteOffset(line: 141) + line[..<column].utf8.count + 3
        let target = try #require(index.target(in: semantics, at: byte))
        #expect(target.displayName == "addSecrecyTag")
        let definition = try #require(target.definitions.first)
        #expect(definition.path == "core/src/main/kotlin/inc/tk/os/module/SecrecyCtx.kt")
        #expect(definition.range.startLine == 17)
        let worker = SemanticQueryWorker()
        let destination = try await worker.resolve(definition, root: root)
        let source = try await SourceStore().load(root: root, path: destination.path)
        #expect(source.displayLineText(source.line(atByte: destination.byteOffset)).contains("fun SecrecyCtx.addSecrecyTag"))
        let references = try await worker.references(of: target.symbol, in: index, root: root)
        #expect(references.groups.first { $0.path == path }?.hits.contains { $0.line == 141 && $0.match == "addSecrecyTag" } == true)
        #expect(references.unmappedCount == 0 && references.unreadablePaths.isEmpty)
        print("Kotlin PR758: \(raw.documents.count) compiler documents, \(semantics.occurrences.count) mapped Contacts occurrences, \(semantics.unmappedCount) unmapped generated constructors; addSecrecyTag -> \(definition.path):\(definition.range.startLine + 1), \(references.referenceCount) references in \(references.fileCount) files")
    }
}
