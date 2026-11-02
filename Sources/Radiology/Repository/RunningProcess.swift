import Foundation

/// Only this wrapper crosses the cancellation boundary. Launch and cancellation
/// are serialized so a cancelled task cannot start an orphaned subprocess.
final class RunningProcess: @unchecked Sendable {
    let process = Process()
    private let lock = NSLock()
    private var cancelled = false

    func launch() throws {
        try lock.withLock {
            if cancelled { throw CancellationError() }
            try process.run()
        }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            if process.isRunning { process.terminate() }
        }
    }
}
