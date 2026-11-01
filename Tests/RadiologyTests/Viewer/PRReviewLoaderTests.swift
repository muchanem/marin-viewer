import Foundation
import Testing
import ViewerCore
@testable import Radiology

@Suite(.enabled(if: ViewerFixture.isAvailable, "needs marin/ and wordbase/ beside the checkout"))
struct PRReviewLoaderTests {
    @Test func loadsEveryChangedFileOfThePR() async throws {
        let document = try await ViewerFixture.document()
        #expect(document.base == ViewerFixture.base && document.head == ViewerFixture.head)
        #expect(document.number == 10640)
        #expect(document.files.count == 30)
        #expect(document.steps.count == 8)
        #expect(document.notes.notes.count == 5)

        // The demo's diff data: http_service.py is a new file of 223 lines.
        let http = try #require(document.file(ViewerFixture.shellbox + "http_service.py"))
        #expect(http.diff.status == .added && http.diff.rows.count == 223 && http.diff.additions == 223)
        #expect(http.headText?.split(separator: "\n", omittingEmptySubsequences: false).count == 224)
        #expect(http.languageName == "Python")
        #expect(http.description?.l1.hasPrefix("Runs a loopback HTTP listener") == true)

        // Highlighting comes from Radiology's tree-sitter queries: line 125
        // is `async def _pump(...)`, so `async`/`def` are keywords and
        // `_pump` a function name.
        let captures = http.headHighlights[124].map(\.capture)
        #expect(captures.contains { $0.hasPrefix("keyword") })
        #expect(captures.contains { $0.hasPrefix("function") })

        // A modified file carries base highlights for its deleted rows.
        let local = try #require(document.file(ViewerFixture.shellbox + "backends/local/machine.py"))
        #expect(local.diff.deletions > 0 && !local.baseHighlights.isEmpty)
        let deleted = try #require(local.diff.rows.first { $0.kind == .deleted && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty })
        #expect(!local.highlights(for: deleted).isEmpty || deleted.text.allSatisfy { !$0.isLetter })

        // Tests and lockfiles are part of the document too.
        #expect(document.file("uv.lock") != nil)
        #expect(document.file("lib/shellbox/tests/test_http_service.py")?.isTest == true)
    }

    @Test func excerptsResolveByNameAgainstTheHead() async throws {
        let document = try await ViewerFixture.document()
        var report: [String] = []
        for step in document.steps {
            for excerpt in step.excerpts {
                #expect(excerpt.problem == nil, "step \(step.id) \(excerpt.path): \(excerpt.problem ?? "")")
                if !excerpt.excerpt.functions.isEmpty { #expect(excerpt.source == .functions) }
                if let fallback = excerpt.excerpt.lineRange, fallback != excerpt.lines {
                    report.append("step \(step.id) \(excerpt.excerpt.functions): \(fallback) -> \(excerpt.lines)")
                }
            }
        }
        print("Excerpts whose resolved lines differ from code-path.json:\n" + report.joined(separator: "\n"))
        // Step 6 starts at `_pump`, line 125 of http_service.py.
        let relay = try #require(document.step(6)?.excerpts.first)
        #expect(relay.path == ViewerFixture.shellbox + "http_service.py")
        #expect(relay.lines.lowerBound == 125)
    }

    @Test func byFileOrderIsSourceThenTestsThenOtherPaths() async throws {
        let document = try await ViewerFixture.document()
        let groups = document.filesInReadingOrder.map(\.displayGroup)
        #expect(groups == groups.sorted())
        #expect(document.filesInReadingOrder.first?.path == ViewerFixture.shellbox + "backends/daytona/bridge.py")
        #expect(document.filesInReadingOrder.last?.path == "vendor/skyrl/uv.lock")
    }

    @Test func definitionsComeFromTheHeadDeclarations() async throws {
        let document = try await ViewerFixture.document()
        let pump = try #require(document.definition(of: "_pump", preferredPath: nil))
        #expect(pump.path == ViewerFixture.shellbox + "http_service.py" && pump.line == 125)
        #expect(document.definition(of: "no_such_symbol_here", preferredPath: nil) == nil)
    }

    @Test func blameIsCachedPerFileAndCommit() async throws {
        let root = try #require(ViewerFixture.dataRoot)
        let store = BlameStore()
        let path = ViewerFixture.shellbox + "http_service.py"
        async let first = store.blame(path: path, commit: ViewerFixture.head, repository: root.appending(path: "marin"))
        async let second = store.blame(path: path, commit: ViewerFixture.head, repository: root.appending(path: "marin"))
        let (a, b) = try await (first, second)
        #expect(a == b && a.lineSHAs.count == 223)
        _ = try await store.blame(path: path, commit: ViewerFixture.head, repository: root.appending(path: "marin"))
        #expect(await store.runs == 1)
        let commit = try #require(a.commit(forNewLine: 1))
        #expect(commit.shortSHA.count == 7 && !commit.firstName.isEmpty)
    }
}
