import Foundation
import Testing
@testable import Radiology

@Suite(.serialized) @MainActor
struct CodePathNavigationTests {
    private func model(_ fixture: GitFixture, preferences: UserDefaults) -> AppModel {
        let cache = IndexCache(root: fixture.directory.appending(path: "code-path-cache"))
        let service = SemanticIndexService(indexers: [], cache: cache, tools: ToolDirectory(url: fixture.directory.appending(path: "tools")))
        let client = FakeGitHubClient(summaries: [1: fixture.summary(number: 1)], mergeBase: fixture.baseSHA)
        return AppModel(preferences: preferences, semantics: SemanticModel(service: service),
                        pullRequests: PullRequestModel(client: client, workingTreeCache: cache))
    }

    private func jump(_ id: UUID, in model: AppModel) async {
        model.goToCodePathStep(id)
        await model.codePathNavigationTask?.value
        await model.awaitCurrentSourceLoad()
    }

    @Test func importJumpBackRelaunchAndPRUseAttachedRepositoryAndAfterCoordinates() async throws {
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let domain = "Radiology.CodePathNavigation.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let model = model(fixture, preferences: preferences)
        await model.openRepository(fixture.attached, selecting: "uni.rs")
        await model.awaitCurrentSourceLoad()
        let buffer = try #require(model.source)
        let origin = buffer.location(atByte: buffer.byteOffset(line: 2, column: 8))
        model.caretMoved(to: origin.byteOffset)
        model.updatePosition(path: buffer.path, byteOffset: 0, line: 1)
        try model.importCodePath("Boot sequence\nsrc/lib.rs:b:Start b\nuni.rs:café:Continue with Unicode")
        let trace = try #require(model.codePaths.selectedPath)
        #expect(model.mode == .codePaths && model.inspectorPanes.bookmarks)
        await jump(trace.steps[0].id, in: model)
        #expect(model.currentLine == 5 && model.source?.path == "src/lib.rs")
        model.goBack()
        await model.awaitCurrentSourceLoad()
        #expect(model.currentCaretLocation == origin)
        let relaunched = self.model(fixture, preferences: preferences)
        await relaunched.openRepository(fixture.attached, selecting: nil)
        #expect(relaunched.codePaths.paths == [trace])
        #expect(BrowserMode.available(reviewing: false).contains(.codePaths))
        #expect(BrowserMode.available(reviewing: false) == [.files, .codePaths, .search])
        #expect(BrowserMode.available(reviewing: true) == [.changes, .files, .codePaths, .search])
        await model.openRepository(fixture.attached, selecting: "src/lib.rs", pullRequest: 1)
        await model.awaitCurrentSourceLoad()
        #expect(model.repository?.root != fixture.attached)
        #expect(model.codePaths.paths == [trace])
        model.setRevision(.before)
        await model.awaitCurrentSourceLoad()
        let before = try #require(model.currentCaretLocation)
        #expect(before.revision == .before)
        await jump(trace.steps[0].id, in: model)
        #expect(model.source?.revision == .after && model.currentLine == 5)
        model.goBack()
        await model.awaitCurrentSourceLoad()
        #expect(model.currentCaretLocation == before)
        await model.openRepository(fixture.origin, selecting: nil)
        #expect(model.codePaths.paths.isEmpty)
        await model.openRepository(fixture.attached, selecting: nil)
        #expect(model.codePaths.paths == [trace])
        let file = fixture.attached.appending(path: "src/lib.rs")
        let original = try String(contentsOf: file, encoding: .utf8)
        try Data(("// inserted\n// another line\n// shifted\n" + original).utf8).write(to: file)
        model.refresh()
        await model.currentRepositoryOpening().task?.value
        await jump(trace.steps[0].id, in: model)
        #expect(model.currentLine == 8 && model.source?.path == "src/lib.rs")
    }

    @Test func missingFilesSymbolsBinaryAndEscapingSymlinksNeverMoveReaderAndNewNavigationWins() async throws {
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let domain = "Radiology.CodePathNavigation.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        try FileManager.default.createSymbolicLink(at: fixture.attached.appending(path: "outside"), withDestinationURL: fixture.origin.appending(path: "src/lib.rs"))
        let model = model(fixture, preferences: preferences)
        await model.openRepository(fixture.attached, selecting: "uni.rs")
        await model.awaitCurrentSourceLoad()
        try model.importCodePath("Unavailable symbols\nmissing.c:f:Missing\nsrc/lib.rs:missing_symbol:Missing symbol\ndata/bin.dat:f:Binary\noutside:f:Escapes checkout\nsrc/lib.rs:a:Valid")
        let trace = try #require(model.codePaths.selectedPath)
        let origin = model.currentCaretLocation
        let history = model.history.entries
        for step in trace.steps.prefix(4) {
            await jump(step.id, in: model)
            #expect(model.codePaths.navigationError != nil)
            #expect(model.currentCaretLocation == origin && model.history.entries == history)
        }
        model.goToCodePathStep(trace.steps[4].id)
        model.caretMoved(to: 3)
        await model.codePathNavigationTask?.value
        #expect(model.source?.path == "uni.rs" && model.currentCaretLocation?.byteOffset == 3)
        model.goToCodePathStep(trace.steps[4].id)
        model.openRepository(fixture.origin)
        await model.currentRepositoryOpening().task?.value
        await model.codePathNavigationTask?.value
        #expect(model.source == nil && model.codePaths.paths.isEmpty && model.codePaths.navigationError == nil)
    }
}
