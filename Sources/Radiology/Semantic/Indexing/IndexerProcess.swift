import Foundation
import Darwin

/// Captured output of a finished indexer run. Both streams are bounded so a
/// chatty tool cannot grow application memory.
struct IndexerRunResult: Sendable, Equatable {
    let exitStatus: Int32
    let terminatedBySignal: Int32?
    let stdoutTail: String
    let stderrHead: String
    let stderrTail: String
    let duration: Duration
    var succeeded: Bool { exitStatus == 0 && terminatedBySignal == nil }
}

/// Launches an indexer in its own process group so cancellation reaches the
/// build tools it spawns (`cargo`, `tsc`, `go list`), and streams its output to
/// temporary files instead of pipes so nothing can deadlock on a full buffer.
final class IndexerProcess: @unchecked Sendable {
    static let tailLimit = 64 * 1024

    let executable: URL
    let arguments: [String]
    let directory: URL
    let environment: [String: String]
    private let lock = NSLock()
    private var pid: pid_t = 0
    private var cancelled = false
    private let stdoutURL: URL
    private let stderrURL: URL

    init(executable: URL, arguments: [String], directory: URL, environment: [String: String]) {
        self.executable = executable
        self.arguments = arguments
        self.directory = directory
        self.environment = environment
        let base = FileManager.default.temporaryDirectory.appending(path: "radiology-indexer-\(UUID().uuidString)")
        stdoutURL = base.appendingPathExtension("out")
        stderrURL = base.appendingPathExtension("err")
    }

    /// The command line as a reader would type it, for diagnostics.
    var commandLine: String {
        ([executable.path] + arguments).map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " ")
    }

    /// Runs to completion, honoring task cancellation by terminating the whole
    /// process group. `progress` receives the latest stderr line periodically.
    func run(progress: (@Sendable (String) -> Void)? = nil) async throws -> IndexerRunResult {
        let started = ContinuousClock.now
        defer {
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }
        try spawn()
        return try await withTaskCancellationHandler {
            let reaper = Task.detached(priority: .utility) { [pid] () -> Int32 in
                var status: Int32 = 0
                while waitpid(pid, &status, 0) < 0 {
                    if errno != EINTR { return -1 }
                }
                return status
            }
            let poller = progress.map { progress in
                Task { [stderrURL] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(400))
                        if let line = Self.lastLine(of: stderrURL) { progress(line) }
                    }
                }
            }
            defer { poller?.cancel() }
            return try finish(status: await reaper.value, started: started)
        } onCancel: {
            cancel()
        }
    }

    private func finish(status: Int32, started: ContinuousClock.Instant) throws -> IndexerRunResult {
        try Task.checkCancellation()
        let exited = status & 0x7F == 0
        let exitStatus = exited ? (status >> 8) & 0xFF : -1
        let signal: Int32? = exited ? nil : status & 0x7F
        return IndexerRunResult(exitStatus: exitStatus, terminatedBySignal: signal,
                                stdoutTail: Self.tail(of: stdoutURL), stderrHead: Self.head(of: stderrURL),
                                stderrTail: Self.tail(of: stderrURL),
                                duration: started.duration(to: .now))
    }

    /// SIGTERM the group, then SIGKILL whatever ignores it.
    func cancel() {
        lock.withLock {
            cancelled = true
            guard pid > 0 else { return }
            killpg(pid, SIGTERM)
            let group = pid
            Task.detached(priority: .utility) {
                try? await Task.sleep(for: .seconds(2))
                killpg(group, SIGKILL)
            }
        }
    }

    private func spawn() throws {
        try lock.withLock {
            if cancelled { throw CancellationError() }
            FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
            FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
            var actions: posix_spawn_file_actions_t?
            posix_spawn_file_actions_init(&actions)
            defer { posix_spawn_file_actions_destroy(&actions) }
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
            posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, stdoutURL.path, O_WRONLY | O_TRUNC, 0)
            posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, stderrURL.path, O_WRONLY | O_TRUNC, 0)
            posix_spawn_file_actions_addchdir_np(&actions, directory.path)
            var attributes: posix_spawnattr_t?
            posix_spawnattr_init(&attributes)
            defer { posix_spawnattr_destroy(&attributes) }
            // A fresh process group whose id is the child's pid, so killpg(pid) reaches descendants.
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))
            posix_spawnattr_setpgroup(&attributes, 0)
            var noSignals = sigset_t()
            sigemptyset(&noSignals)
            posix_spawnattr_setsigmask(&attributes, &noSignals)
            var defaults = sigset_t()
            sigfillset(&defaults)
            posix_spawnattr_setsigdefault(&attributes, &defaults)
            let argv: [UnsafeMutablePointer<CChar>?] = ([executable.path] + arguments).map { strdup($0) } + [nil]
            let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
            defer {
                argv.forEach { free($0) }
                envp.forEach { free($0) }
            }
            var child: pid_t = 0
            let result = posix_spawn(&child, executable.path, &actions, &attributes, argv, envp)
            guard result == 0 else {
                throw BrowserError.message("Could not launch \(executable.lastPathComponent): \(String(cString: strerror(result))).")
            }
            pid = child
        }
    }

    static func tail(of url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(tailLimit) ? size - UInt64(tailLimit) : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        var text = String(decoding: data, as: UTF8.self)
        if start > 0, let newline = text.firstIndex(of: "\n") { text = "…" + text[text.index(after: newline)...] }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func head(of url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: tailLimit)) ?? Data()
        var text = String(decoding: data, as: UTF8.self)
        if data.count == tailLimit, let newline = text.lastIndex(of: "\n") {
            text = String(text[...newline]) + "…"
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func lastLine(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        guard size > 0 else { return nil }
        let start = size > 4096 ? size - 4096 : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        // Progress output often rewrites one line with carriage returns.
        return text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).last.map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}
