import Foundation
import Testing
@testable import ViewerCore

struct ChipTests {
    @Test func encodesTheSidecarShape() throws {
        let chip = Chip(
            kind: .selection, path: "lib/shellbox/src/shellbox/http_service.py", lines: 125...147,
            symbol: "_pump", commit: "01a8bb8f0bea2dde1de90274ed695c25147b9f06",
            label: "http_service.py:125-147 · _pump")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(chip), as: UTF8.self)
        #expect(json.contains(#""kind":"selection""#))
        #expect(json.contains(#""lines":[125,147]"#))
        #expect(try JSONDecoder().decode(Chip.self, from: Data(json.utf8)) == chip)
    }

    @Test func omitsAbsentFieldsAndRejectsReversedLines() throws {
        let file = Chip(kind: .file, path: "README.md", commit: "abc", label: "README.md")
        let json = String(decoding: try JSONEncoder().encode(file), as: UTF8.self)
        #expect(!json.contains("lines") && !json.contains("symbol"))
        let reversed = #"{"kind":"line","lines":[9,3],"commit":"abc","label":"x"}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Chip.self, from: Data(reversed.utf8))
        }
    }
}
