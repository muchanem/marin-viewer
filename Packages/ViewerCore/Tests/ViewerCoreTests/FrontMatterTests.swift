import Foundation
import Testing
@testable import ViewerCore

struct FrontMatterTests {
    /// The file entry example from DESIGN.md §6, front matter verbatim.
    static let designExample = """
    ---
    kind: file                 # file | system | pr | reviewer
    path: lib/shellbox/src/shellbox/http_service.py
    commit: 01a8bb8f0bea2dde1de90274ed695c25147b9f06   # the code this description describes
    updated: 2026-11-01T16:40:00Z
    by: claude-opus-5-5 prep 10640    # model and run that wrote the layers
    l1: Runs a loopback HTTP listener inside a machine and relays each request ...
    l2: Frames are newline-delimited JSON checked by strict Pydantic models ...
    l3:
      - First paragraph ...
    system: shellbox           # file entries name their subsystem
    ---

    ## Symbols

    ### `_pump`
    l1: Waits on the receive task and every pending handler, and writes each response as its task finishes.
    l2: Up to 16 handlers run at once.

    ## Notes

    - 2026-11-01 · 01a8bb8 · session 3f2a… · The relay's failure behavior under a stuck model endpoint ...
    """

    @Test func designExampleDecodes() throws {
        let entry = try WordbaseEntry(markdown: Self.designExample)
        #expect(entry.header.kind == .file)
        #expect(entry.header.path == "lib/shellbox/src/shellbox/http_service.py")
        #expect(entry.header.commit == "01a8bb8f0bea2dde1de90274ed695c25147b9f06")
        #expect(entry.header.updated == "2026-11-01T16:40:00Z")
        #expect(entry.header.by == "claude-opus-5-5 prep 10640")
        #expect(entry.header.l3 == ["First paragraph ..."])
        #expect(entry.header.system == "shellbox")
        #expect(entry.symbols == [SymbolEntry(name: "_pump", layers: Layers(
            l1: "Waits on the receive task and every pending handler, and writes each response as its task finishes.",
            l2: "Up to 16 handlers run at once."))])
        #expect(entry.notes == [EntryNote(date: "2026-11-01", commit: "01a8bb8", session: "3f2a…",
                                          text: "The relay's failure behavior under a stuck model endpoint ...")])
    }

    /// PyYAML's style, as in the fixture's `pr.md`: lists at the key's indent,
    /// single quotes with doubled apostrophes.
    @Test func pyYAMLStyle() throws {
        let value = try FrontMatter.parse("""
        number: 10640
        prepared_at: '2026-10-30T00:00:00Z'
        l2: 'the primary''s network namespace'
        l3:
        - First.
        - 'Harbor''s Compose import (#10628) builds on these types.'
        empty:
        next: x
        """)
        #expect(value["number"] == .int(10640))
        #expect(value["prepared_at"] == .string("2026-10-30T00:00:00Z"))
        #expect(value["l2"] == .string("the primary's network namespace"))
        #expect(value["l3"] == .list([.string("First."), .string("Harbor's Compose import (#10628) builds on these types.")]))
        #expect(value["empty"] == .null)
        #expect(value["next"] == .string("x"))
    }

    /// js-yaml and the `yaml` package fold long scalars at 80 columns.
    @Test func foldedAndBlockScalars() throws {
        let value = try FrontMatter.parse("""
        l1: Runs a loopback HTTP listener inside a machine and relays each request
          over a process session to a handler on the host.
        l2: "A \\"quoted\\" value that
          continues"
        l3:
          - >-
            Folded block
            on two lines.

            Second paragraph.
          - |
            literal
              indented
        sha: 0123456
        flag: true
        none: ~
        """)
        #expect(value["l1"] == .string("Runs a loopback HTTP listener inside a machine and relays each request over a process session to a handler on the host."))
        #expect(value["l2"] == .string("A \"quoted\" value that continues"))
        #expect(value["l3"] == .list([.string("Folded block on two lines.\nSecond paragraph."), .string("literal\n  indented\n")]))
        #expect(value["sha"] == .string("0123456"), "leading zeros stay strings")
        #expect(value["flag"] == .bool(true))
        #expect(value["none"] == .null)
    }

    /// Nested maps, lists of maps and `- - a` lists, as in the fixture's
    /// `systems/shellbox.md` diagram.
    @Test func nestedBlocksAndFlowLists() throws {
        let value = try FrontMatter.parse("""
        diagram:
          layout:
            mode: grid
            direction: RIGHT
          nodes:
          - id: b-local
            label: Local
            sub: bubblewrap
            grid: {}
            paths:
            - lib/shellbox/src/shellbox/backends/local/
          - id: shellbox
            label: Shellbox
            sub: machines, tasks
          edges:
          - - shellbox
            - b-local
          - [shellbox, iris, uses]
        uses: []
        """)
        let diagram = value["diagram"]
        #expect(diagram?["layout"] == .map(["mode": .string("grid"), "direction": .string("RIGHT")]))
        #expect(diagram?["edges"] == .list([
            .list([.string("shellbox"), .string("b-local")]),
            .list([.string("shellbox"), .string("iris"), .string("uses")]),
        ]))
        guard case .list(let nodes)? = diagram?["nodes"] else { Issue.record("nodes"); return }
        #expect(nodes.count == 2)
        #expect(nodes[0]["paths"] == .list([.string("lib/shellbox/src/shellbox/backends/local/")]))
        #expect(nodes[0]["grid"] == .map([:]))
        #expect(nodes[1]["sub"] == .string("machines, tasks"))
        #expect(value["uses"] == .list([]))
    }

    @Test func unsupportedOrBrokenYAMLFailsLoudly() {
        #expect(throws: FrontMatterError.self) { try FrontMatter.parse("a: 'open\nb: c") }
        #expect(throws: FrontMatterError.self) { try FrontMatter.parse("a: {b: c}") }
        #expect(throws: FrontMatterError.self) { try FrontMatter.parse("a: b\n    c: d\n  e: f") }
        #expect(throws: FrontMatterError.self) { try FrontMatter.parse("a: 1\na: 2") }
        #expect(throws: WordbaseError.missingFrontMatter) { try WordbaseEntry(markdown: "# no front matter\n") }
        #expect(FrontMatter.split("---\r\nkind: file\r\n---\r\nbody") ?? ("", "") == ("kind: file", "body"))
    }
}
