import Foundation
import Testing
import ViewerCore
@testable import Radiology

/// A transport that answers from a script instead of a child process: no test starts a model
/// session, reads a real key or posts to GitHub.
final class ScriptedTransport: SidecarTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var onLine: (@Sendable (Data) -> Void)?
    private var onExit: (@Sendable (String) -> Void)?
    private var sentLines: [JSONValue] = []
    /// Called for every message the app sends; returns the lines the sidecar answers with.
    var script: @Sendable (JSONValue) -> [JSONValue]

    init(script: @escaping @Sendable (JSONValue) -> [JSONValue] = ScriptedTransport.acknowledge) {
        self.script = script
    }

    var sent: [JSONValue] { lock.withLock { sentLines } }
    func sent(type: String) -> [JSONValue] { sent.filter { $0["type"]?.string == type } }

    func start(onLine: @escaping @Sendable (Data) -> Void, onExit: @escaping @Sendable (String) -> Void) throws {
        lock.withLock {
            self.onLine = onLine
            self.onExit = onExit
        }
    }

    func send(_ line: Data) throws {
        let message = try JSONDecoder().decode(JSONValue.self, from: line)
        let (replies, onLine) = lock.withLock { () -> ([JSONValue], (@Sendable (Data) -> Void)?) in
            sentLines.append(message)
            return (script(message), self.onLine)
        }
        for reply in replies { try onLine?(reply.line()) }
    }

    /// Pushes an unsolicited sidecar line, such as a `stream.delta` or an `app.request`.
    func emit(_ message: JSONValue) throws {
        let onLine = lock.withLock { self.onLine }
        try onLine?(message.line())
    }

    func exit(_ reason: String) {
        let onExit = lock.withLock { self.onExit }
        onExit?(reason)
    }

    func stop() {}

    /// Answers every request with an empty `response`.
    static let acknowledge: @Sendable (JSONValue) -> [JSONValue] = { message in
        guard let id = message["id"] else { return [] }
        return [["type": "response", "id": id, "result": [:]]]
    }

    static func response(_ message: JSONValue, _ result: JSONValue) -> JSONValue {
        ["type": "response", "id": message["id"] ?? .null, "result": result]
    }
}

/// Polls `condition` on the main actor, yielding between checks, for up to two seconds.
@MainActor func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<400 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// A small prepared PR in the wordbase layout, written to a temporary directory: three steps,
/// a PR map with a diagram for step 2, a subsystem page and three notes.
struct ViewerFixture {
    let root: URL
    var paths: ViewerPaths { ViewerPaths(root: root) }
    static let head = "01a8bb8f0bea2dde1de90274ed695c25147b9f06"
    static let base = "8a92f90382559206b03ead1afbbd32c35f68fcff"
    static let src = "lib/shellbox/src/shellbox/"

    static func make() throws -> ViewerFixture {
        let root = FileManager.default.temporaryDirectory.appending(path: "viewer-fixture-\(UUID().uuidString)", directoryHint: .isDirectory)
        let pr = root.appending(path: "wordbase/prs/10640", directoryHint: .isDirectory)
        let systems = root.appending(path: "wordbase/systems", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: pr, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: systems, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "wordbase/prs/99"), withIntermediateDirectories: true)
        try Self.prMarkdown.write(to: pr.appending(path: "pr.md"), atomically: true, encoding: .utf8)
        try Self.codePath.write(to: pr.appending(path: "code-path.json"), atomically: true, encoding: .utf8)
        try Self.diagrams.write(to: pr.appending(path: "diagrams.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: pr.appending(path: "files.json"), atomically: true, encoding: .utf8)
        try Self.notes.write(to: pr.appending(path: "notes.jsonl"), atomically: true, encoding: .utf8)
        try Self.system.write(to: systems.appending(path: "shellbox.md"), atomically: true, encoding: .utf8)
        return ViewerFixture(root: root)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    /// ViewerCore's `CodeLocation` is built from wordbase JSON, so tests decode one too.
    static func location(_ path: String, function: String) throws -> CodeLocation {
        let json = try JSONEncoder().encode(["path": path, "function": function])
        return try JSONDecoder().decode(CodeLocation.self, from: json)
    }

    static func change(_ path: String, _ status: FileChange.Status = .modified, add: Int = 3, del: Int = 1) -> FileChange {
        FileChange(path: path, oldPath: nil, status: status, beforeBlob: "", afterBlob: "", additions: add, deletions: del)
    }

    static let changes: [FileChange] = [
        change(src + "task.py", .added, add: 151, del: 0),
        change(src + "backends/local/machine.py", add: 300, del: 40),
        change(src + "http_service.py", .added, add: 223, del: 0),
        change("lib/shellbox/tests/test_task.py", .added, add: 80, del: 0),
        change("lib/rolloutengine/src/rolloutengine/rollout.py", add: 4, del: 2),
    ]

    static let headFiles: [String] = changes.map(\.path).filter { $0.hasPrefix("lib/shellbox/") } + [
        src + "machine.py", src + "backends/local/cgroup.py", src + "backends/qemu/machine.py", "lib/shellbox/tests/conftest.py",
    ]

    /// The PR as `ViewerPRLoader` would build it, without git.
    func loadPR() throws -> ViewerPR {
        let directory = paths.prDirectory(10640)
        let changes = Self.changes
        return ViewerPR(number: 10640, directory: directory, wordbase: try PRWordbase(directory: directory), changes: changes,
                        system: ViewerPRLoader.system(covering: changes.map(\.path), in: paths.wordbase), headFiles: Self.headFiles)
    }

    static let prMarkdown = """
    ---
    kind: pr
    number: 10640
    repo: marin-community/marin
    title: Add persistent container tasks and host capabilities
    author: rjpower
    state: MERGED
    head: \(head)
    base: \(base)
    merge_base: \(base)
    prepared_at: '2026-10-30T00:00:00Z'
    session_id: demo-10640
    l1: Shellbox can start a task as a group of named containers.
    l2: A caller lists containers in a `TaskSpec`.
    l3:
    - Local machines also accept prepared OCI images.
    ---
    """

    static let codePath = """
    [
      {"id": 1, "title": "Describe the task", "l1": "A `TaskSpec` names containers.", "node": "spec",
       "excerpts": [{"path": "\(src)task.py", "functions": ["TaskSpec"], "lines": [45, 111]}]},
      {"id": 2, "title": "Start the members", "l1": "The local backend starts each member.", "node": "group",
       "excerpts": [{"path": "\(src)backends/local/machine.py", "functions": ["LocalMachineFactory.create_task"], "lines": [1029, 1091]}]},
      {"id": 3, "title": "Wait for readiness", "l1": "Probes run until ready.", "node": "runtime",
       "excerpts": [{"path": "\(src)task.py", "functions": ["Task.wait_ready", "Task.close"], "lines": [137, 151]}]}
    ]
    """

    static let diagrams = """
    {"pr": {"layout": {"mode": "grid"}, "nodes": [
        {"id": "spec", "label": "TaskSpec", "sub": "containers, probes", "step": 1, "grid": {"col": 0, "row": 0}},
        {"id": "group", "label": "Primary", "sub": "guest helper", "step": 2, "grid": {"col": 1, "row": 0}},
        {"id": "runtime", "label": "Readiness", "sub": "", "step": 3, "grid": {"col": 2, "row": 0}}],
      "edges": [["spec", "group"], ["group", "runtime", "probes"]]},
     "steps": {"2": {"layout": {"mode": "grid"}, "nodes": [
        {"id": "ct", "label": "create_task", "sub": "checks policy", "at": {"path": "\(src)backends/local/machine.py", "function": "LocalMachineFactory.create_task"}, "grid": {"col": 0, "row": 0}},
        {"id": "cl", "label": "caller", "sub": "", "grid": {"col": 1, "row": 0}}],
      "edges": [["cl", "ct"]]}}}
    """

    static let notes = """
    {"id": "f1", "path": "\(src)http_service.py", "line": 133, "side": "head", "commit": "\(head)", "severity": "medium", "status": "draft", "who": "review session", "l1": "A retry can arrive while the host still counts 16.", "l2": "The guest starts its timer first.", "created": "2026-10-30T00:00:00Z", "updated": "2026-10-30T00:00:00Z"}
    {"id": "f2", "path": "\(src)task.py", "line": 133, "side": "head", "commit": "\(head)", "severity": "low", "status": "draft", "who": "review session", "l1": "`Task.endpoint` raises a bare StopIteration.", "l2": "", "created": "2026-10-30T00:00:00Z", "updated": "2026-10-30T00:00:00Z"}
    {"id": "f3", "path": "\(src)task.py", "line": 60, "side": "head", "commit": "\(head)", "severity": "low", "status": "posted", "who": "you", "l1": "Posted earlier.", "l2": "", "github_comment_id": 7, "created": "2026-10-30T00:00:00Z", "updated": "2026-10-30T00:00:00Z"}

    """

    static let system = """
    ---
    kind: system
    name: shellbox
    l1: Sandboxed machines for agent tasks.
    members:
    - lib/shellbox/
    diagram:
      layout:
        mode: grid
      nodes:
      - id: rolloutengine
        label: RolloutEngine
        sub: runs trials
        paths:
        - lib/rolloutengine/
        grid:
          col: 0
          row: 0
      - id: shellbox
        label: Shellbox
        sub: machines
        paths:
        - lib/shellbox/
        grid:
          col: 1
          row: 0
      - id: iris
        label: Iris
        sub: cluster
        paths:
        - lib/iris/
        grid:
          col: 2
          row: 0
      edges:
      - [rolloutengine, shellbox]
      - [shellbox, iris]
    ---
    Shellbox.
    """
}
