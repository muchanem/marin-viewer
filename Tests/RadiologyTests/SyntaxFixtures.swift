import Foundation
import Testing
@testable import Radiology

/// Representative source for every registered grammar, loaded from the test
/// bundle so the fixtures stay readable as real code.
enum SyntaxFixtures {
    static func buffer(_ name: String) throws -> SourceBuffer {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"),
                               "fixture \(name) is missing from the test bundle")
        return try SourceBuffer(path: name, data: try Data(contentsOf: url))
    }

    static func snapshot(_ name: String) async throws -> (SourceBuffer, SyntaxSnapshot) {
        let buffer = try buffer(name)
        let snapshot = try #require(try await SyntaxWorker().parse(buffer), "\(name) produced no snapshot")
        return (buffer, snapshot)
    }

    /// All fixtures, one per registered language plus the JSX and Kotlin-script dialects.
    static let names = ["sample.swift", "sample.rs", "sample.go", "sample.py", "sample.js",
                        "sample.jsx", "sample.ts", "sample.tsx", "sample.kt", "sample.kts", "sample.c", "sample.cpp"]
}

extension SyntaxSnapshot {
    func highlight(named name: String, text: String, in buffer: SourceBuffer) -> Bool {
        highlights.contains { $0.name == name && buffer.text(in: $0.byteRange) == text }
    }

    func symbol(_ kind: String, _ name: String) -> Bool {
        symbols.contains { $0.kind == kind && $0.name == name }
    }
}

extension SourceBuffer {
    func text(in range: Range<Int>) -> String { String(decoding: data[range], as: UTF8.self) }
}
