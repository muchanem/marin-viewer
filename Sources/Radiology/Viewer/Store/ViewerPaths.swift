import Foundation

/// Where the viewer's data lives (DESIGN.md §4): the Marin clone, the wordbase, poller state,
/// prompts and the built sidecar. Every path defaults under `~/openathena/marin-viewer` and can be
/// moved with a launch argument, which is how tests and scratch runs keep off the real data.
struct ViewerPaths: Sendable, Equatable {
    var root: URL
    var marin: URL
    var wordbase: URL
    var state: URL
    var prompts: URL
    /// The sidecar package directory; the client runs `dist/main.js` inside it.
    var sidecar: URL
    /// An explicit `node`; nil searches the usual places.
    var node: URL?

    static let defaultRoot = URL(filePath: NSHomeDirectory()).appending(path: "openathena/marin-viewer", directoryHint: .isDirectory)

    init(root: URL = ViewerPaths.defaultRoot, marin: URL? = nil, wordbase: URL? = nil, state: URL? = nil,
         prompts: URL? = nil, sidecar: URL? = nil, node: URL? = nil) {
        self.root = root
        self.marin = marin ?? root.appending(path: "marin", directoryHint: .isDirectory)
        self.wordbase = wordbase ?? root.appending(path: "wordbase", directoryHint: .isDirectory)
        self.state = state ?? root.appending(path: "state", directoryHint: .isDirectory)
        self.prompts = prompts ?? root.appending(path: "prompts", directoryHint: .isDirectory)
        self.sidecar = sidecar ?? root.appending(path: "sidecar", directoryHint: .isDirectory)
        self.node = node
    }

    init(arguments: ViewerLaunchArguments, environment: [String: String] = ProcessInfo.processInfo.environment) {
        let root = (arguments.root ?? environment["MARIN_VIEWER_ROOT"]).map { URL(filePath: $0, directoryHint: .isDirectory) }
        self.init(root: root ?? Self.defaultRoot,
                  marin: arguments.marin.map { URL(filePath: $0, directoryHint: .isDirectory) },
                  wordbase: arguments.wordbase.map { URL(filePath: $0, directoryHint: .isDirectory) },
                  state: arguments.state.map { URL(filePath: $0, directoryHint: .isDirectory) },
                  sidecar: arguments.sidecar.map { URL(filePath: $0, directoryHint: .isDirectory) },
                  node: arguments.node.map { URL(filePath: $0) })
    }

    var sidecarScript: URL { sidecar.appending(path: "dist/main.js") }
    var prsDirectory: URL { wordbase.appending(path: "prs", directoryHint: .isDirectory) }
    func prDirectory(_ number: Int) -> URL { prsDirectory.appending(path: String(number), directoryHint: .isDirectory) }

    /// PR numbers with a prepared directory under `wordbase/prs/`, newest first.
    func preparedPRs() -> [Int] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: prsDirectory.path)) ?? []
        return names.compactMap(Int.init)
            .filter { FileManager.default.fileExists(atPath: prDirectory($0).appending(path: "pr.md").path) }
            .sorted(by: >)
    }

    /// `node` for the sidecar: the explicit one, then PATH, then Homebrew, then the newest nvm
    /// install (a Finder launch has a minimal PATH).
    func resolveNode(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        if let node, FileManager.default.isExecutableFile(atPath: node.path) { return node }
        let manager = FileManager.default
        var candidates = (environment["PATH"] ?? "").split(separator: ":").map { URL(filePath: String($0)).appending(path: "node") }
        candidates += ["/opt/homebrew/bin/node", "/usr/local/bin/node"].map { URL(filePath: $0) }
        let nvm = URL(filePath: NSHomeDirectory()).appending(path: ".nvm/versions/node", directoryHint: .isDirectory)
        let versions = ((try? manager.contentsOfDirectory(atPath: nvm.path)) ?? [])
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        candidates += versions.map { nvm.appending(path: "\($0)/bin/node") }
        return candidates.first { manager.isExecutableFile(atPath: $0.path) }
    }
}

/// Viewer launch arguments, in the style of `LaunchArguments`:
/// `--viewer-pr N` opens prepared PR N from the wordbase in the main window, `--viewer-root PATH`
/// moves the data root, and `--viewer-marin`, `--viewer-wordbase`, `--viewer-state`,
/// `--viewer-sidecar` and `--viewer-node` move one path each.
struct ViewerLaunchArguments: Sendable, Equatable {
    let pullRequest: Int?
    let root: String?
    let marin: String?
    let wordbase: String?
    let state: String?
    let sidecar: String?
    let node: String?

    init(_ arguments: [String]) {
        pullRequest = Self.value(of: "--viewer-pr", in: arguments).flatMap(Int.init)
        root = Self.value(of: "--viewer-root", in: arguments)
        marin = Self.value(of: "--viewer-marin", in: arguments)
        wordbase = Self.value(of: "--viewer-wordbase", in: arguments)
        state = Self.value(of: "--viewer-state", in: arguments)
        sidecar = Self.value(of: "--viewer-sidecar", in: arguments)
        node = Self.value(of: "--viewer-node", in: arguments)
    }

    private static func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.count > index + 1 else { return nil }
        return arguments[index + 1]
    }
}
