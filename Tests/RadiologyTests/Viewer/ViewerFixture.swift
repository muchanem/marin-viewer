import Foundation
@testable import Radiology

/// PR #10640 from the gitignored data beside the viewer checkout: the Marin
/// clone (`marin/`) and the wordbase fixture (`wordbase/prs/10640/`). Found
/// by walking up from this file, so a worktree under `.claude/worktrees`
/// uses the main checkout's data. Tests that need it are skipped without it.
enum ViewerFixture {
    static let base = "8a92f90382559206b03ead1afbbd32c35f68fcff"
    static let head = "01a8bb8f0bea2dde1de90274ed695c25147b9f06"
    static let shellbox = "lib/shellbox/src/shellbox/"

    static let dataRoot: URL? = {
        var directory = URL(filePath: #filePath).deletingLastPathComponent()
        let manager = FileManager.default
        while directory.path != "/" {
            if manager.fileExists(atPath: directory.appending(path: "marin/.git").path),
               manager.fileExists(atPath: directory.appending(path: "wordbase/prs/10640/pr.md").path) {
                return directory
            }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }()

    static var isAvailable: Bool { dataRoot != nil }

    /// The loaded document, built once per test run.
    static func document() async throws -> PRReviewDocument {
        try await Cache.shared.document()
    }

    /// Where snapshot PNGs go, when `DIFF_READER_SNAPSHOT_DIR` is set.
    static var snapshotDirectory: URL? {
        ProcessInfo.processInfo.environment["DIFF_READER_SNAPSHOT_DIR"].map { URL(filePath: $0) }
    }

    /// The demo's clock for blame ages (`Date.parse("2026-11-01")`).
    static let demoNow = Date(timeIntervalSince1970: 1_793_491_200)

    private actor Cache {
        static let shared = Cache()
        private var task: Task<PRReviewDocument, Error>?

        func document() async throws -> PRReviewDocument {
            if let task { return try await task.value }
            guard let root = ViewerFixture.dataRoot else { throw BrowserError.message("No #10640 fixture data.") }
            let task = Task {
                try await PRReviewLoader().load(prDirectory: root.appending(path: "wordbase/prs/10640"),
                                                repository: root.appending(path: "marin"))
            }
            self.task = task
            return try await task.value
        }
    }
}
