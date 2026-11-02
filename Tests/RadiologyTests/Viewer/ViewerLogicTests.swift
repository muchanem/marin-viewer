import AppKit
import Foundation
import Testing
import ViewerCore
@testable import Radiology

@Suite struct ViewerLogicTests {
    @Test func movingOneStepToTheTopMovesOnlyThatStep() {
        #expect(StepOrdering.moved(original: Array(1...8), reordered: [6, 1, 2, 3, 4, 5, 7, 8]) == [6])
        #expect(StepOrdering.moved(original: Array(1...8), reordered: Array(1...8)).isEmpty)
        #expect(StepOrdering.moved(original: [1, 2, 3], reordered: [3, 2, 1]).count == 2)
    }

    @Test func normalizedOrdersDropUnknownStepsAndKeepMissingOnes() {
        #expect(StepOrdering.normalized([6, 6, 9, 1], steps: Array(1...8)) == [6, 1, 2, 3, 4, 5, 7, 8])
    }

    @Test func boxMenusOfferTheStepDiagramOnlyOnThePRMap() throws {
        let session = DiagramLayoutResult.Node(id: "session", label: "ProcessSession", step: 4, x: 0, y: 0, w: 90, h: 34)
        let hasDiagram: (Int) -> Bool = { [2, 4, 6, 7].contains($0) }
        #expect(DiagramBoxAction.actions(for: session, in: .pr, hasStepDiagram: hasDiagram) == [.ask, .goToStep(4), .openStepDiagram(4)])
        #expect(DiagramBoxAction.actions(for: session, in: .pr, hasStepDiagram: hasDiagram)
            .map { $0.title(label: session.label) } == ["Ask About ProcessSession", "Go to Step 4", "Open Step Diagram"])
        let spec = DiagramLayoutResult.Node(id: "spec", label: "TaskSpec", step: 1, x: 0, y: 0, w: 90, h: 34)
        #expect(DiagramBoxAction.actions(for: spec, in: .pr, hasStepDiagram: hasDiagram) == [.ask, .goToStep(1)])
        let at = try ShellFixture.location("lib/shellbox/src/shellbox/http_service.py", function: "_pump")
        let pump = DiagramLayoutResult.Node(id: "pu", label: "_pump", step: 6, at: at, x: 0, y: 0, w: 90, h: 34)
        #expect(DiagramBoxAction.actions(for: pump, in: .step(6), hasStepDiagram: hasDiagram)
            == [.ask, .openCode(at), .openCodeInNewWindow(path: at.path), .goToStep(6)])
    }

    @Test func chipLabelsMatchTheDemo() throws {
        let shortener = PathShortener(system: SystemPage(name: "shellbox", layers: nil, members: ["lib/shellbox/"], diagram: nil))
        let src = ShellFixture.src
        #expect(ChipFactory.file(src + "http_service.py", commit: "c", shortener: shortener).label == "file http_service.py")
        #expect(ChipFactory.file("lib/rolloutengine/x.py", commit: "c", shortener: shortener).label == "file lib/rolloutengine/x.py")
        let at = try JSONDecoder().decode(CodeLocation.self, from: Data(#"{"path":"lib/shellbox/src/shellbox/http_service.py","function":"_pump"}"#.utf8))
        let box = ChipFactory.box(label: "_pump", at: at, commit: "c",
                                  shortener: shortener, line: 125)
        #expect(box.label == "_pump · http_service.py:125" && box.kind == .box && box.symbol == "_pump")
        #expect(ChipFactory.box(label: "Host handler", at: nil, commit: "c", shortener: shortener).label == "component Host handler")
        let code = ChipFactory.code(path: src + "http_service.py", lines: 125...147, symbol: "_pump", commit: "c", shortener: shortener)
        #expect(code.label == "http_service.py:125-147 · _pump" && code.lines == 125...147)
        #expect(ChipFactory.code(path: src + "task.py", lines: 9...9, symbol: nil, commit: "c", shortener: shortener).kind == .line)
    }

    @Test func stepCoversByLineOrFunction() throws {
        let step = try JSONDecoder().decode(PRStep.self, from: Data(#"{"id":6,"title":"Relay","l1":"","excerpts":[{"path":"a.py","functions":["_pump","serve_http"],"lines":[125,223]}]}"#.utf8))
        #expect(step.covers(path: "a.py", line: 130, function: nil))
        #expect(!step.covers(path: "a.py", line: 300, function: nil))
        #expect(step.covers(path: "a.py", line: nil, function: "serve_http"))
        #expect(!step.covers(path: "b.py", line: 130, function: nil))
        #expect(step.fallbackLine(path: "a.py", function: "_pump") == 125)
    }

    @Test func systemMapMarksHereTouchedAndDimmed() {
        let changed = ["lib/shellbox/src/shellbox/task.py", "lib/rolloutengine/x.py"]
        #expect(SystemNodeMark.mark(id: "shellbox", paths: ["lib/shellbox/"], system: "shellbox", changed: changed) == .here)
        #expect(SystemNodeMark.mark(id: "rolloutengine", paths: ["lib/rolloutengine/"], system: "shellbox", changed: changed) == .touched)
        #expect(SystemNodeMark.mark(id: "iris", paths: ["lib/iris/"], system: "shellbox", changed: changed) == .dimmed)
        #expect(SystemNodeMark.mark(id: "x", paths: nil, system: "shellbox", changed: changed) == .plain)
    }

    @Test func viewerTabsLeadWithTheCodePathAndKeepRadiologysOtherwise() {
        #expect(BrowserMode.available(reviewing: false, viewerPR: true) == [.steps, .changes, .files, .search])
        #expect(BrowserMode.available(reviewing: true, viewerPR: false) == [.changes, .files, .codePaths, .search])
        #expect(BrowserMode.available(reviewing: false, viewerPR: false) == [.files, .codePaths, .search])
    }

    @Test func launchArgumentsMoveEachPath() {
        let arguments = ViewerLaunchArguments(["Radiology", "--viewer-pr", "10640", "--viewer-root", "/tmp/r", "--viewer-state", "/tmp/s",
                                               "--viewer-node", "/opt/node"])
        #expect(arguments.pullRequest == 10640)
        let paths = ViewerPaths(arguments: arguments, environment: [:])
        #expect(paths.root.path == "/tmp/r" && paths.marin.path == "/tmp/r/marin" && paths.wordbase.path == "/tmp/r/wordbase")
        #expect(paths.state.path == "/tmp/s" && paths.sidecarScript.path == "/tmp/r/sidecar/dist/main.js" && paths.node?.path == "/opt/node")
        #expect(ViewerLaunchArguments(["Radiology"]).pullRequest == nil)
    }

    @Test func preparedPRsListOnlyDirectoriesWithAPRPage() throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        #expect(fixture.paths.preparedPRs() == [10640])
    }

    @Test func childEnvironmentDropsAPIKeysAndCarriesThePaths() {
        let base = ["ANTHROPIC_API_KEY": "sk-secret", "CLAUDE_API_KEY": "k", "ANTHROPIC_AUTH_TOKEN": "t", "PATH": "/usr/bin", "KEEP": "1"]
        let paths = ViewerPaths(root: URL(filePath: "/tmp/root"))
        let environment = SidecarEnvironment.child(base: base, paths: paths, node: URL(filePath: "/opt/node/bin/node"))
        #expect(environment["ANTHROPIC_API_KEY"] == nil && environment["CLAUDE_API_KEY"] == nil && environment["ANTHROPIC_AUTH_TOKEN"] == nil)
        #expect(environment["KEEP"] == "1" && environment["MARIN_VIEWER_WORDBASE"] == "/tmp/root/wordbase")
        #expect(environment["PATH"]?.hasPrefix("/usr/bin:/opt/node/bin") == true)
        #expect(!environment.values.contains("sk-secret"))
    }

    @Test func focusedTreeShowsChangedFoldersFirstAndCollapsesTests() throws {
        let src = ShellFixture.src
        let tree = FocusedTree(root: "lib/shellbox/", headFiles: ShellFixture.headFiles, changes: ShellFixture.changes,
                               stepsByPath: [src + "task.py": [1, 3]], draftPaths: [src + "task.py"], toggled: [])
        let ids = tree.rows.map(\.id)
        #expect(ids.first == "root:lib/shellbox/")
        guard case .file(let task, _)? = tree.rows.first(where: { $0.filePath == src + "task.py" }) else {
            Issue.record("task.py has no row")
            return
        }
        #expect(task.steps == [1, 3] && task.hasDraftNote && task.name == "task.py")
        // Tests start closed, and their files are not listed.
        #expect(tree.rows.contains { if case .directory(_, "tests", _, 1, false) = $0 { true } else { false } })
        #expect(!ids.contains("file:lib/shellbox/tests/test_task.py"))
        // machine.py is unchanged next to task.py: behind "+ 1 unchanged".
        #expect(tree.rows.contains { if case .unchangedToggle("q:src/shellbox", _, 1, false) = $0 { true } else { false } })
        // backends/qemu holds no change.
        #expect(tree.rows.contains { if case .unchangedFolders(let count, let names) = $0 { count == 1 && names == ["src/shellbox/backends/qemu"] } else { false } })
        #expect(ids.contains("elsewhere") && ids.contains("else:lib/rolloutengine/src/rolloutengine/rollout.py"))
        let opened = FocusedTree(root: "lib/shellbox/", headFiles: ShellFixture.headFiles, changes: ShellFixture.changes,
                                 stepsByPath: [:], draftPaths: [], toggled: ["t:tests", "q:src/shellbox"])
        #expect(opened.rows.map(\.id).contains("file:lib/shellbox/tests/test_task.py"))
        #expect(opened.rows.map(\.id).contains("quiet:\(src)machine.py"))
    }

    @Test @MainActor func boxSizesComeFromTheAppFont() {
        let node = try! JSONDecoder().decode(DiagramNode.self, from: Data(#"{"id":"a","label":"serve_http relay","sub":"bounded frames"}"#.utf8))
        let size = DiagramMetrics.size(of: node, code: false)
        let label = DiagramMetrics.width(of: "serve_http relay", font: .systemFont(ofSize: 10.5))
        #expect(size.height == 34 && size.width == (label + 16).rounded())
        let code = DiagramMetrics.size(of: node, code: true)
        #expect(code.width >= size.width - 1)
        let bare = try! JSONDecoder().decode(DiagramNode.self, from: Data(#"{"id":"b","label":"x","sub":""}"#.utf8))
        #expect(DiagramMetrics.size(of: bare, code: false) == CGSize(width: 56, height: 26))
    }

    @Test func layoutResultsDecodeFromTheSidecar() throws {
        let json = #"""
        {"mode":"grid","width":460,"height":196,"scale":0.9,"minScale":0.8,"overflow":false,"natural":{"width":500,"height":210},
         "nodes":[{"id":"a","label":"A","sub":"s","x":4,"y":4,"w":60,"h":30,"step":2,"at":{"path":"p.py","function":"f"}}],
         "groups":[{"label":"G","members":["a"],"x":0,"y":0,"w":100,"h":60,"label_box":{"x":8,"y":6,"w":20,"h":12}}],
         "edges":[{"from":"a","to":"a","points":[[1,2],[3,4]],"label":"l","label_box":{"x":1,"y":1,"w":5,"h":5}}],"warnings":[]}
        """#
        let result = try JSONDecoder().decode(DiagramLayoutResult.self, from: Data(json.utf8))
        #expect(result.nodes[0].at?.function == "f" && result.groups[0].labelBox.w == 20 && result.edges[0].cgPoints.count == 2)
    }
}
