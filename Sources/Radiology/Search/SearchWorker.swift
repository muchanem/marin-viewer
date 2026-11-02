import Foundation

actor SearchWorker {
    static let resultLimit = 5_000

    /// Emits batches before the process exits; stderr goes to a temporary file
    /// so a full stderr pipe cannot deadlock the stdout reader.
    func search(root: URL, options: SearchOptions, receive: @escaping @Sendable ([SearchMatch]) async -> Void) async throws -> Bool {
        guard let rg = ToolLocator.executable("rg") else {
            throw BrowserError.message("ripgrep was not found. Install it with brew install ripgrep, then rebuild or relaunch Marin Viewer.")
        }
        let command = RunningProcess()
        let output = Pipe()
        let errorURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let errors = try FileHandle(forWritingTo: errorURL)
        defer { try? errors.close(); try? FileManager.default.removeItem(at: errorURL) }
        command.process.executableURL = rg
        command.process.arguments = options.arguments
        command.process.currentDirectoryURL = root
        command.process.standardOutput = output
        command.process.standardError = errors
        return try await withTaskCancellationHandler {
            try command.launch()
            var batch: [SearchMatch] = []
            var count = 0
            var lastDelivery = ContinuousClock.now
            var limited = false
            for try await line in output.fileHandleForReading.bytes.lines {
                try Task.checkCancellation()
                let matches = try SearchMatch.decode(Data(line.utf8))
                batch.append(contentsOf: matches.prefix(max(0, Self.resultLimit - count)))
                count += matches.count
                if batch.count >= 40 || lastDelivery.duration(to: .now) > .milliseconds(40) {
                    await receive(batch)
                    batch.removeAll(keepingCapacity: true)
                    lastDelivery = .now
                }
                if count >= Self.resultLimit {
                    limited = true
                    command.cancel()
                    break
                }
            }
            if !batch.isEmpty { await receive(batch) }
            command.process.waitUntilExit()
            try Task.checkCancellation()
            guard limited || [0, 1].contains(command.process.terminationStatus) else {
                let message = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? "Search failed."
                throw BrowserError.message(message.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return limited
        } onCancel: { command.cancel() }
    }
}
