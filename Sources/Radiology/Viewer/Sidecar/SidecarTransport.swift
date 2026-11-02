import Foundation

/// Byte transport for the sidecar's JSON lines. The app uses `ProcessSidecarTransport`; tests use
/// a scripted transport, so no test ever starts a model session or posts to GitHub.
protocol SidecarTransport: AnyObject, Sendable {
    /// Starts the transport. `onLine` receives each complete stdout line without its newline;
    /// `onExit` fires once when the other side goes away. Both may be called on any thread.
    func start(onLine: @escaping @Sendable (Data) -> Void, onExit: @escaping @Sendable (String) -> Void) throws
    func send(_ line: Data) throws
    func stop()
}

/// Environment variables that must never reach an interactive session. The sidecar strips them
/// too; removing them here keeps the key out of the child process tree entirely.
enum SidecarEnvironment {
    static let strippedKeys: Set<String> = ["ANTHROPIC_API_KEY", "CLAUDE_API_KEY", "ANTHROPIC_AUTH_TOKEN"]

    /// The child's environment: ours minus the API keys, plus a PATH that finds `git`, `rg` and
    /// `claude` when the app was launched from Finder, plus the viewer's data paths.
    static func child(base: [String: String] = ProcessInfo.processInfo.environment, paths: ViewerPaths,
                      node: URL) -> [String: String] {
        var environment = base.filter { !strippedKeys.contains($0.key) }
        let home = NSHomeDirectory()
        var path = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for addition in [node.deletingLastPathComponent().path, "\(home)/.local/bin", "\(home)/.claude/local",
                         "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] where !path.contains(addition) {
            path.append(addition)
        }
        environment["PATH"] = path.joined(separator: ":")
        environment["HOME"] = environment["HOME"] ?? home
        environment["MARIN_VIEWER_ROOT"] = paths.root.path
        environment["MARIN_VIEWER_MARIN"] = paths.marin.path
        environment["MARIN_VIEWER_WORDBASE"] = paths.wordbase.path
        environment["MARIN_VIEWER_STATE"] = paths.state.path
        environment["MARIN_VIEWER_PROMPTS"] = paths.prompts.path
        return environment
    }
}

/// The sidecar as a child process: `node <sidecar>/dist/main.js`, JSON lines on stdin/stdout,
/// diagnostics on stderr (kept as a bounded tail, never echoed with the environment).
final class ProcessSidecarTransport: SidecarTransport, @unchecked Sendable {
    let node: URL
    let script: URL
    let environment: [String: String]
    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var errorTail: [String] = []
    private var exited = false

    init(node: URL, script: URL, environment: [String: String]) {
        self.node = node
        self.script = script
        self.environment = environment
    }

    /// The last lines the sidecar wrote to stderr.
    var stderrTail: [String] { lock.withLock { errorTail } }

    func start(onLine: @escaping @Sendable (Data) -> Void, onExit: @escaping @Sendable (String) -> Void) throws {
        let process = Process()
        process.executableURL = node
        process.arguments = [script.path]
        process.environment = environment
        process.currentDirectoryURL = script.deletingLastPathComponent().deletingLastPathComponent()
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            for line in self.appendAndSplit(chunk) { onLine(line) }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self, !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self.appendError(String(decoding: chunk, as: UTF8.self))
        }
        process.terminationHandler = { [weak self] finished in
            guard let self else { return }
            let reason = "the sidecar exited with status \(finished.terminationStatus)"
            let first = self.lock.withLock { () -> Bool in
                defer { self.exited = true }
                return !self.exited
            }
            if first { onExit(reason) }
        }
        try process.run()
        lock.withLock {
            self.process = process
            self.input = stdin.fileHandleForWriting
        }
    }

    func send(_ line: Data) throws {
        let handle = lock.withLock { exited ? nil : input }
        guard let handle else { throw SidecarError.notRunning }
        try handle.write(contentsOf: line + Data([0x0A]))
    }

    func stop() {
        let (process, input) = lock.withLock { (self.process, self.input) }
        try? input?.close()
        if let process, process.isRunning { process.terminate() }
    }

    private func appendAndSplit(_ chunk: Data) -> [Data] {
        lock.withLock {
            buffer.append(chunk)
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                if !line.isEmpty { lines.append(Data(line)) }
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            return lines
        }
    }

    private func appendError(_ text: String) {
        lock.withLock {
            errorTail.append(contentsOf: text.split(separator: "\n").map(String.init))
            if errorTail.count > 200 { errorTail.removeFirst(errorTail.count - 200) }
        }
    }
}

enum SidecarError: Error, LocalizedError, Equatable {
    case notRunning
    case unavailable(String)
    case failed(String)
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .notRunning: "The sidecar is not running."
        case .unavailable(let reason): reason
        case .failed(let message): message
        case .timedOut(let what): "The sidecar did not answer \(what) in time."
        }
    }
}
