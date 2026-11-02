import AppKit
import Testing
@testable import Radiology

/// Exercises actual compiler-produced Kotlin identities through the PR reader,
/// native selection callback, Context, semantic commands, revision switches,
/// reference commits, and exact-caret Back. No Gradle is needed at test time.
@Suite(.serialized)
@MainActor
struct PRKotlinNavigationTests {
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        try await IndexingTests.waitUntil(.seconds(30), condition)
    }

    private func setup() async throws -> (GitFixture, AppModel) {
        let fixture = try await Task.detached { try GitFixture.make() }.value
        do {
            let commits = try await Task.detached { () -> (String, String) in
                try GitFixture.run(["checkout", "-q", "-b", "kotlin", fixture.baseSHA], in: fixture.origin)
                for name in ["settings.gradle.kts", "build.gradle.kts", KotlinIndexingTests.readerPath,
                             KotlinIndexingTests.storePath, "src/main/kotlin/Noise.kt"] {
                    let text = try String(contentsOf: KotlinIndexingTests.fixtureRoot.appending(path: name), encoding: .utf8)
                    try GitFixture.write(name == KotlinIndexingTests.readerPath ? text.replacingOccurrences(of: "read(2)", with: "read(1)") : text,
                                         to: fixture.origin.appending(path: name))
                }
                try GitFixture.run(["add", "-A"], in: fixture.origin)
                try GitFixture.run(["commit", "-q", "-m", "Kotlin base"], in: fixture.origin)
                let base = try GitFixture.run(["rev-parse", "HEAD"], in: fixture.origin)
                let text = try String(contentsOf: KotlinIndexingTests.fixtureRoot.appending(path: KotlinIndexingTests.readerPath), encoding: .utf8)
                try GitFixture.write(text, to: fixture.origin.appending(path: KotlinIndexingTests.readerPath))
                try GitFixture.run(["commit", "-q", "-am", "Change Kotlin call argument"], in: fixture.origin)
                return (base, try GitFixture.run(["rev-parse", "HEAD"], in: fixture.origin))
            }.value
            let summary = PullRequestSummary(number: 1, title: "Kotlin call", state: "OPEN", baseRefName: "kotlin", baseRefOid: commits.0,
                                             headRefName: "kotlin", headRefOid: commits.1, isCrossRepository: false, updatedAt: .now,
                                             mergeCommit: nil, author: nil)
            let cache = IndexCache(root: fixture.directory.appending(path: "index-cache"))
            let compilerOutput = KotlinIndexingTests.fixtureRoot.appending(path: "index.scip")
            let fake = FakeIndexer(id: "kotlin-fixture", displayName: "Kotlin fixture", defaultEncoding: .utf16,
                                   script: "cp '\(compilerOutput.path)' \"$1\"", marker: "build.gradle.kts", installable: true, languages: ["Kotlin"])
            let service = SemanticIndexService(indexers: [fake], cache: cache, tools: ToolDirectory(url: fixture.directory.appending(path: "tools")))
            let client = FakeGitHubClient(summaries: [1: summary], mergeBase: commits.0)
            let preferences = try #require(UserDefaults(suiteName: "RadiologyTests." + UUID().uuidString))
            let model = AppModel(preferences: preferences, semantics: SemanticModel(service: service),
                                 pullRequests: PullRequestModel(client: client, workingTreeCache: cache))
            model.openRepository(fixture.attached)
            try await waitUntil { !model.isOpening && model.repository != nil }
            model.openPullRequest(1)
            try await waitUntil { model.review != nil && !model.isOpening && model.repository != nil && model.semantics.hasIndex }
            model.openFile(KotlinIndexingTests.readerPath)
            try await waitUntil { model.source?.revision == .after && model.syntax?.path == KotlinIndexingTests.readerPath
                && model.semantics.documentSemantics?.path == KotlinIndexingTests.readerPath && model.reviewHighlights != nil }
            return (fixture, model)
        } catch {
            fixture.remove()
            throw error
        }
    }

    @Test func changedBlockCaretReferencesAndDefinitionBackRemainInAfter() async throws {
        let (fixture, model) = try await setup()
        defer { fixture.remove() }
        let source = try #require(model.source)
        #expect(model.semanticAvailability == .available)
        #expect(model.reviewHighlights?.lineRanges.contains { $0.contains(4) } == true)
        let call = (source.text as NSString).range(of: "read(2)").location
        let native = ReaderTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 250))
        native.isEditable = false
        native.isSelectable = true
        native.string = source.text
        let coordinator = SourceViewerCoordinator()
        coordinator.buffer = source
        coordinator.textView = native
        coordinator.onCaret = { model.caretMoved(to: $0) }
        native.delegate = coordinator
        let history = model.history.entries
        let navigation = model.navigationRevision
        native.setSelectedRange(NSRange(location: call + 1, length: 0))
        let departure = source.location(atByte: source.byteOffset(forUTF16: call + 1))
        #expect(model.currentCaretLocation == departure)
        #expect(model.semantics.caretTarget?.displayName == "read")
        #expect(model.context.underCaret?.target.displayName == "read")
        #expect(model.context.declaration?.declaration.name == "changed")
        #expect(model.history.entries == history && model.navigationRevision == navigation)

        model.findReferencesAtCaret()
        try await waitUntil { if case .loaded = model.context.references { true } else { false } }
        guard case .loaded(let results) = model.context.references else { return }
        let definition = try #require(results.groups.first { $0.path == KotlinIndexingTests.storePath }?.hits.first { $0.isDefinition })
        #expect(results.referenceCount == 1)
        let target = try #require(model.semantics.caretTarget?.definitions.first)
        // Deliberately give this destination a Before preference: semantic
        // coordinates still belong to After, and Back restores the exact byte.
        let changedFile = try #require(model.review?.change(touching: source.path))
        model.pullRequests.revisionChoices[changedFile.id] = .before
        model.updatePosition(path: source.path, byteOffset: 0, line: 1)
        model.goToDefinitionAtCaret()
        try await waitUntil { model.source?.path == target.path && model.source?.revision == .after && !model.isLoadingSource }
        #expect(model.source?.line(atByte: model.currentCaretLocation?.byteOffset ?? 0) == 4)
        model.goBack()
        try await waitUntil { model.source?.path == source.path && model.source?.revision == .after && !model.isLoadingSource }
        #expect(model.navigationTarget == departure && model.currentCaretLocation == departure)
        model.commitReference(id: definition.id)
        try await waitUntil { model.source?.path == definition.location.path && !model.isLoadingSource }
        #expect(model.navigationTarget == definition.location.with(revision: .after))
        #expect(model.currentCaretLocation?.revision == .after)
        model.goBack()
        try await waitUntil { model.source?.path == source.path && !model.isLoadingSource }
        #expect(model.currentCaretLocation == departure)
    }

    @Test func beforeClearsSemanticsAndAfterRemapsUsingCachedUTF16Contract() async throws {
        let (fixture, model) = try await setup()
        defer { fixture.remove() }
        let source = try #require(model.source)
        let call = (source.text as NSString).range(of: "read(2)").location
        model.caretMoved(to: source.byteOffset(forUTF16: call + 1))
        #expect(model.context.underCaret?.target.displayName == "read")
        model.setRevision(.before)
        try await waitUntil { model.source?.revision == .before && !model.isLoadingSource && model.syntax != nil }
        let before = try #require(model.source)
        let beforeCall = (before.text as NSString).range(of: "read(1)").location
        model.caretMoved(to: before.byteOffset(forUTF16: beforeCall + 1))
        #expect(model.currentCaretLocation?.revision == .before)
        #expect(model.context.declaration?.declaration.name == "changed")
        #expect(model.semantics.caretTarget == nil && model.context.underCaret == nil && model.semantics.documentSemantics == nil)
        #expect(model.semanticAvailability == .revisionNotIndexed)
        model.setRevision(.after)
        try await waitUntil { model.source?.revision == .after && model.semantics.documentSemantics?.path == source.path }
        model.caretMoved(to: source.byteOffset(forUTF16: call + 1))
        #expect(model.context.underCaret?.target.displayName == "read")
        #expect(model.semantics.documentSemantics?.unmappedCount == 0)
        model.refresh()
        try await waitUntil { !model.pullRequests.isRefreshing }
        #expect(model.context.underCaret?.target.displayName == "read")
        #expect(model.currentCaretLocation?.revision == .after)
    }
}
