import Foundation
@testable import ViewerCore

/// Test data: `Fixtures/pr10640` holds `git diff -U100000` and
/// `git blame --porcelain` output for PR #10640 (base 8a92f90, head
/// 01a8bb8) and `expected.json`, the matching files and commit table cut
/// verbatim from `demo/pr10640.json`. `Fixtures/edge` holds diffs from a
/// scratch repository: added, deleted, binary, renamed, mode-only, empty
/// and no-newline-at-end files.
enum Fixtures {
    static func text(_ path: String) throws -> String {
        let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures").appendingPathComponent(path)
        return String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    /// `expected.json` as JSON objects.
    static func expected() throws -> [String: Any] {
        let data = Data(try text("pr10640/expected.json").utf8)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    static func expectedFile(_ path: String) throws -> [String: Any] {
        let files = try expected()["files"] as! [[String: Any]]
        return files.first { $0["path"] as? String == path }!
    }

    /// A file's `lines` from the demo data, as rows.
    static func expectedRows(_ path: String) throws -> [DiffRow] {
        let lines = try expectedFile(path)["lines"] as! [[Any]]
        return lines.map { line in
            let kind = DiffRow.Kind(rawValue: line[0] as! String)!
            return DiffRow(kind: kind, oldLine: line[1] as? Int, newLine: line[2] as? Int, text: line[3] as! String)
        }
    }

    /// The repository root (`marin-viewer`), for the live wordbase fixture.
    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// Synthetic rows from a compact spec: `c` context, `d` deleted, `a` added.
    static func rows(_ spec: String) -> [DiffRow] {
        var old = 1, new = 1
        return spec.map { tag in
            switch tag {
            case "d": defer { old += 1 }; return DiffRow(kind: .deleted, oldLine: old, newLine: nil, text: "old \(old)")
            case "a": defer { new += 1 }; return DiffRow(kind: .added, oldLine: nil, newLine: new, text: "new \(new)")
            default: defer { old += 1; new += 1 }; return DiffRow(kind: .context, oldLine: old, newLine: new, text: "line \(new)")
            }
        }
    }
}
