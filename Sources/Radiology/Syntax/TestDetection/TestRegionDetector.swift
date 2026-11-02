import Foundation
import SwiftTreeSitter

/// Finds test-only regions in one parsed file from real grammar node shapes:
/// Rust attributes and `cfg` predicates, Kotlin annotations, Python test
/// classes and pytest conventions, JavaScript/TypeScript test-framework
/// calls. Never scans braces or strings. Detection is conservative: anything
/// that could also run in production stays visible. See plans/source-filters.md.
struct TestRegionDetector {
    struct Result: Equatable, Sendable {
        var regions: [TestRegion] = []
        /// The whole file compiles only for tests (Rust `#![cfg(test)]`).
        var isTestOnlyDocument = false
    }

    static let supportedLanguageIDs: Set<String> = ["rust", "kotlin", "python", "javascript", "typescript", "tsx"]

    let languageID: String
    let buffer: SourceBuffer
    var data: Data { buffer.data }

    func detect(root: Node) -> Result {
        var regions: [TestRegion] = []
        switch languageID {
        case "rust":
            if rustBodyIsTestOnly(root.childNodes()) { return Result(isTestOnlyDocument: true) }
            rustRegions(in: root, into: &regions)
        case "kotlin":
            kotlinRegions(in: root, into: &regions)
        case "python":
            pythonRegions(in: root, into: &regions)
        case "javascript", "typescript", "tsx":
            ecmascriptRegions(in: root, into: &regions)
        default:
            break
        }
        return Result(regions: normalized(regions))
    }

    // MARK: - Shared helpers

    func text(_ node: Node) -> String {
        let range = node.intByteRange
        guard range.upperBound <= data.count else { return "" }
        return String(decoding: data[range], as: UTF8.self)
    }

    /// The region from `first` (pulled back over directly adjacent doc
    /// comments among `siblings`) through `last`, plus a trailing comment on
    /// last's final line, expanded to whole lines where the code owns them.
    func region(siblings: [Node], from firstIndex: Int, through lastIndex: Int,
                evidence: TestRegion.Evidence) -> TestRegion {
        let last = siblings[lastIndex]
        var startIndex = firstIndex
        while startIndex > 0, isDocComment(siblings[startIndex - 1]),
              line(of: siblings[startIndex - 1].intByteRange.upperBound - 1) + 1
                >= line(of: siblings[startIndex].intByteRange.lowerBound) {
            startIndex -= 1
        }
        var end = last.intByteRange.upperBound
        if lastIndex + 1 < siblings.count, isComment(siblings[lastIndex + 1]),
           line(of: siblings[lastIndex + 1].intByteRange.lowerBound) == line(of: max(0, end - 1)) {
            end = siblings[lastIndex + 1].intByteRange.upperBound
        }
        return TestRegion(byteRange: expandedToLines(siblings[startIndex].intByteRange.lowerBound..<end),
                          evidence: evidence)
    }

    func isComment(_ node: Node) -> Bool {
        guard let type = node.nodeType else { return false }
        return type == "comment" || type.hasSuffix("_comment")
    }

    /// `///` and `/** */` documentation comments (Rust, Kotlin KDoc, JSDoc).
    func isDocComment(_ node: Node) -> Bool {
        guard isComment(node) else { return false }
        let spelling = text(node)
        return (spelling.hasPrefix("///") && !spelling.hasPrefix("////"))
            || (spelling.hasPrefix("/**") && !spelling.hasPrefix("/**/"))
    }

    func line(of byte: Int) -> Int { buffer.line(atByte: byte) }

    /// Starts at the line start when only indentation precedes; ends at the
    /// line terminator (before any `\r`) when only whitespace follows. The
    /// newline itself stays outside, so following code keeps its own line.
    func expandedToLines(_ range: Range<Int>) -> Range<Int> {
        var start = range.lowerBound
        let lineStart = buffer.lineStarts[line(of: start) - 1]
        if data[lineStart..<start].allSatisfy({ $0 == 0x20 || $0 == 0x09 }) { start = lineStart }
        var end = range.upperBound
        var cursor = end
        while cursor < data.count, data[cursor] == 0x20 || data[cursor] == 0x09 || data[cursor] == 0x0D { cursor += 1 }
        if cursor == data.count || data[cursor] == 0x0A {
            end = cursor > end && data[cursor - 1] == 0x0D ? cursor - 1 : cursor
        }
        return start..<max(start, end)
    }

    /// Sorted, disjoint, outermost regions. Neighbours separated only by
    /// whitespace merge, so a run of test declarations reads as one region.
    func normalized(_ regions: [TestRegion]) -> [TestRegion] {
        let sorted = regions.filter { !$0.byteRange.isEmpty }.sorted {
            $0.byteRange.lowerBound == $1.byteRange.lowerBound
                ? $0.byteRange.upperBound > $1.byteRange.upperBound
                : $0.byteRange.lowerBound < $1.byteRange.lowerBound
        }
        var output: [TestRegion] = []
        for region in sorted {
            guard let previous = output.last else { output.append(region); continue }
            let gapIsBlank = previous.byteRange.upperBound >= region.byteRange.lowerBound
                || data[previous.byteRange.upperBound..<region.byteRange.lowerBound]
                    .allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D || $0 == 0x0A }
            if gapIsBlank {
                let upper = max(previous.byteRange.upperBound, region.byteRange.upperBound)
                output[output.count - 1] = TestRegion(byteRange: previous.byteRange.lowerBound..<upper,
                                                      evidence: previous.evidence)
            } else {
                output.append(region)
            }
        }
        return output
    }
}
