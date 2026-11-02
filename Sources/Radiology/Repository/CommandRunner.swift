import Foundation

actor CommandRunner {
    func run(_ executable: URL, arguments: [String], directory: URL, environment: [String: String]? = nil) async throws -> Data {
        let command = RunningProcess()
        if let environment { command.process.environment = environment }
        let output = Pipe()
        let errorURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: errorURL)
        }
        command.process.executableURL = executable
        command.process.arguments = arguments
        command.process.currentDirectoryURL = directory
        command.process.standardOutput = output
        command.process.standardError = errorHandle
        return try await withTaskCancellationHandler {
            try command.launch()
            // Blocking pipe I/O stays on this worker actor, never on MainActor.
            let data = try output.fileHandleForReading.readToEnd() ?? Data()
            command.process.waitUntilExit()
            try Task.checkCancellation()
            guard command.process.terminationStatus == 0 else {
                let message = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? "Command failed."
                throw BrowserError.message(message.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return data
        } onCancel: { command.cancel() }
    }
}
