import Foundation
import Testing
@testable import ViewerCore

struct WordbaseTests {
    /// `WORDBASE_PR_FIXTURE` points the live test at another copy.
    static let fixture = ProcessInfo.processInfo.environment["WORDBASE_PR_FIXTURE"].map { URL(fileURLWithPath: $0) }
        ?? Fixtures.repositoryRoot.appendingPathComponent("wordbase/prs/10640")

    /// The live fixture decodes once workstream 0 has rewritten it to the
    /// revised §6 shape (`functions` lists in `code-path.json`).
    static var fixtureHasNewShape: Bool {
        let codePath = fixture.appendingPathComponent("code-path.json")
        guard let data = try? Data(contentsOf: codePath) else { return false }
        return String(decoding: data, as: UTF8.self).contains("\"functions\"")
    }

    static var wordbaseExists: Bool {
        FileManager.default.fileExists(atPath: Fixtures.repositoryRoot.appendingPathComponent("wordbase").path)
    }

    @Test(.enabled(if: WordbaseTests.fixtureHasNewShape, "wordbase/prs/10640 is not in the revised §6 shape yet"))
    func liveFixtureDecodes() throws {
        let pr = try PRWordbase(directory: Self.fixture)
        #expect(pr.description.header.kind == .pr)
        #expect(pr.description.header.head == "01a8bb8f0bea2dde1de90274ed695c25147b9f06")
        #expect(pr.description.header.base == "8a92f90382559206b03ead1afbbd32c35f68fcff")
        #expect(pr.description.header.l3?.count == 3)
        #expect(pr.codePath.map(\.id) == Array(1...8))
        let relay = try #require(pr.step(id: 6)?.excerpts.first { $0.path.hasSuffix("/http_service.py") })
        #expect(relay.functions.contains("serve_http"))
        #expect(pr.diagrams.diagram(forStep: 6) != nil)
        #expect(pr.diagrams.pr.nodes.allSatisfy { $0.step != nil })
        for diagram in [pr.diagrams.pr] + pr.diagrams.steps.values where diagram.layout?.mode == .grid {
            #expect(diagram.nodes.allSatisfy { $0.grid != nil }, "grid mode puts every node in a cell")
        }
        #expect(pr.notes.notes.map(\.id) == ["f1", "f2", "f3", "f4", "f5"])
        #expect(pr.files["lib/shellbox/src/shellbox/http_service.py"]?.l1.hasPrefix("Runs a loopback HTTP listener") == true)
    }

    /// Every markdown entry in the live wordbase decodes.
    @Test(.enabled(if: WordbaseTests.wordbaseExists, "no wordbase checkout"))
    func liveEntriesDecode() throws {
        let root = Fixtures.repositoryRoot.appendingPathComponent("wordbase")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "md" && !$0.path.contains("/.git/") && !$0.path.contains("/prs/") }
        #expect(!files.isEmpty)
        for url in files {
            let entry = try WordbaseEntry(markdown: String(decoding: try Data(contentsOf: url), as: UTF8.self))
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            switch entry.header.kind {
            case .file:
                #expect(entry.header.path.map { relative == $0 + ".md" } == true, "\(relative)")
                #expect(entry.header.l1 != nil, "\(relative)")
            case .system:
                #expect(entry.header.diagram != nil, "\(relative)")
            case .reviewer:
                // The fixture has used both "Notes" and "How you review".
                #expect(!(entry.notes + entry.notes(inSection: "How you review")).isEmpty, "\(relative)")
            case .pr:
                Issue.record("pr entry outside prs/: \(relative)")
            }
        }
    }

    /// Samples written to the revised §6, while the fixture is rewritten.
    @Test func codePathAndDiagramsInTheRevisedShape() throws {
        let codePath = try JSONDecoder().decode([CodePathStep].self, from: Data("""
        [{ "id": 1, "title": "Describe the task", "l1": "A caller lists containers.", "l2": "More.", "node": "spec",
           "excerpts": [{ "path": "lib/shellbox/src/shellbox/task.py", "functions": ["ServiceEndpoint", "TaskSpec"], "lines": [45, 111] },
                        { "path": "lib/shellbox/src/shellbox/process_framing.py", "functions": [], "lines": [1, 54] }] }]
        """.utf8))
        let excerpts = codePath[0].excerpts
        #expect(excerpts[0].functions == ["ServiceEndpoint", "TaskSpec"] && !excerpts[0].isWholeModule)
        #expect(excerpts[0].lineRange == 45...111)
        #expect(excerpts[1].isWholeModule && excerpts[1].lineRange == 1...54)
        #expect(Excerpt(path: "x", lines: [9, 3]).lineRange == nil)
        // The old single `function` key is no longer the contract.
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Excerpt.self, from: Data(#"{"path": "x", "function": "f", "lines": [1, 2]}"#.utf8))
        }

        let diagrams = try JSONDecoder().decode(PRDiagrams.self, from: Data("""
        { "pr": { "nodes": [{ "id": "relay", "label": "serve_http relay", "sub": "bounded frames", "step": 6,
                              "paths": ["lib/shellbox/src/shellbox/http_service.py"] },
                            { "id": "b-local", "label": "Local", "sub": "bubblewrap", "paths": ["lib/shellbox/src/shellbox/backends/local/"] },
                            { "id": "qemu", "label": "QEMU", "sub": "ShellSim", "paths": ["lib/shellbox/src/shellbox/backends/qemu/"] }],
                  "edges": [["relay", "b-local"], ["b-local", "qemu", "falls back"]] },
          "steps": { "6": { "layout": { "mode": "grid", "direction": "RIGHT" },
                            "nodes": [{ "id": "pu", "label": "_pump", "sub": "16 in flight", "grid": { "col": 0, "row": 1, "span": 2 },
                                        "at": { "path": "lib/shellbox/src/shellbox/http_service.py", "function": "_pump" } }],
                            "edges": [], "groups": [{ "label": "Host process", "members": ["pu"] }] } } }
        """.utf8))
        #expect(diagrams.pr.layout == nil && diagrams.pr.groups.isEmpty)
        #expect(diagrams.pr.edges == [DiagramEdge(from: "relay", to: "b-local"), DiagramEdge(from: "b-local", to: "qemu", label: "falls back")])
        let step = try #require(diagrams.diagram(forStep: 6))
        #expect(step.layout == DiagramLayout(mode: .grid, direction: .right))
        #expect(step.nodes[0].grid == GridCell(col: 0, row: 1, span: 2))
        #expect(step.nodes[0].at == CodeLocation(path: "lib/shellbox/src/shellbox/http_service.py", function: "_pump"))
        #expect(diagrams.diagram(forStep: 3) == nil)

        let changed = ["lib/shellbox/src/shellbox/http_service.py", "lib/shellbox/src/shellbox/backends/local/cgroup.py"]
        #expect(diagrams.pr.nodes.map { $0.isTouched(byChangedPaths: changed) } == [true, true, false])
        #expect(step.nodes[0].isTouched(byChangedPaths: changed) == nil, "no paths, no touched mark")

        // Round trip: edges re-encode as arrays.
        let again = try JSONDecoder().decode(PRDiagrams.self, from: try JSONEncoder().encode(diagrams))
        #expect(again == diagrams)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DiagramLayout.self, from: Data(#"{"mode": "free"}"#.utf8))
        }
    }

    @Test func prDescriptionAndSystemEntrySamples() throws {
        let pr = try PRDescription(markdown: """
        ---
        kind: pr
        number: 10640
        head: 01a8bb8f0bea2dde1de90274ed695c25147b9f06
        base: 8a92f90382559206b03ead1afbbd32c35f68fcff
        merge_base: 8a92f90382559206b03ead1afbbd32c35f68fcff
        prepared_at: '2026-10-30T00:00:00Z'
        session_id: demo-10640
        l1: Shellbox can start a task as a group of named containers.
        l3:
        - One.
        - 'Two''s.'
        ---
        """)
        #expect(pr.header.number == 10640 && pr.header.mergeBase == pr.header.base && pr.header.sessionID == "demo-10640")
        #expect(pr.header.layers == Layers(l1: "Shellbox can start a task as a group of named containers.", l3: ["One.", "Two's."]))
        #expect(pr.sections.isEmpty && pr.symbols.isEmpty)

        let system = try WordbaseEntry(markdown: """
        ---
        kind: system
        name: shellbox
        members:
        - lib/shellbox/
        uses:
        - iris
        used_by:
        - taskforge
        - harbor
        diagram:
          layout:
            mode: auto
            direction: DOWN
          nodes:
          - id: shellbox
            label: Shellbox
            sub: machines, tasks
          - id: b-local
            label: Local
            sub: bubblewrap
            paths:
            - lib/shellbox/src/shellbox/backends/local/
            grid:
              col: 1
              row: 0
          edges:
          - - shellbox
            - b-local
        lint:
        - stock contrast
        ---

        ## Notes

        - 2026-11-01 · 01a8bb8 · Relay throughput was the open design question
          in the #10640 review.
        - A bullet without the date prefix.
        """)
        #expect(system.header.kind == .system && system.header.name == "shellbox")
        #expect(system.header.usedBy == ["taskforge", "harbor"] && system.header.uses == ["iris"])
        #expect(system.header.diagram?.layout == DiagramLayout(mode: .auto, direction: .down))
        #expect(system.header.diagram?.nodes[1].grid == GridCell(col: 1, row: 0))
        #expect(system.header.diagram?.edges == [DiagramEdge(from: "shellbox", to: "b-local")])
        #expect(system.header.lint == ["stock contrast"])
        #expect(system.notes == [
            EntryNote(date: "2026-11-01", commit: "01a8bb8", text: "Relay throughput was the open design question in the #10640 review."),
            EntryNote(text: "A bullet without the date prefix."),
        ])
    }

    @Test func badSymbolBodyNamesTheSymbol() {
        let markdown = "---\nkind: file\npath: x.py\n---\n\n## Symbols\n\n### `f`\nl2: no l1\n"
        #expect {
            try WordbaseEntry(markdown: markdown)
        } throws: { error in
            if case WordbaseError.badSymbol("f", _) = error { return true }
            return false
        }
    }
}
