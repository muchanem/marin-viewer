import Foundation
import Testing
@testable import Radiology

struct CodePathTests {
    @Test func parsesOrderedStepsCRLFUnicodeAndEscapedSymbolsAndRoundTrips() throws {
        let trace = try CodePathParser.parse("\u{FEFF}Boot: café 🚀\r\n\r\nsrc/start.cc:Kernel\\:\\:boot:Starts: CPU setup\r\nsrc/next.swift:run(label\\:):Continues the boot\r\n")
        #expect(trace.title == "Boot: café 🚀")
        #expect(trace.steps.map(\.path) == ["src/start.cc", "src/next.swift"])
        #expect(trace.steps.map(\.function) == ["Kernel::boot", "run(label:)"])
        #expect(trace.steps[0].description == "Starts: CPU setup")
        let roundTrip = try CodePathParser.parse(trace.text)
        #expect(roundTrip.title == trace.title)
        #expect(roundTrip.steps.map(\.function) == trace.steps.map(\.function))
        #expect(roundTrip.steps.map(\.description) == trace.steps.map(\.description))
        #expect(roundTrip.steps.map(\.path) == trace.steps.map(\.path))
        #expect(Set(trace.steps.map(\.id)).count == 2)
    }

    @Test(arguments: ["", "\na.c:f:hello", "Title", "Title\na.c:f", "Title\n/etc/passwd:f:hello",
                      "Title\n../outside:f:hello", "Title\na/../b:f:hello", "Title\na.c::hello",
                      "Title\na.c:f: ", "Title\na.c:f:okay\nb.c:missing"])
    func rejectsMalformedImports(_ text: String) {
        #expect(throws: (any Error).self) { try CodePathParser.parse(text) }
    }

    @Test func diagnosesActualInputLineAndCapsInputSize() {
        do {
            _ = try CodePathParser.parse("Title\n\na.c:f:okay\nnot a step")
            Issue.record("Expected invalid step")
        } catch { #expect(error.localizedDescription.hasPrefix("Line 4:")) }
        #expect(throws: (any Error).self) { try CodePathParser.parse(String(repeating: "x", count: CodePathParser.maximumBytes + 1)) }
    }

    @MainActor @Test func persistsMultipleTracesPerCanonicalRepositoryAndDeletesOnlySelection() throws {
        let domain = "Radiology.CodePaths.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let root = URL(filePath: NSTemporaryDirectory()).resolvingSymlinksInPath()
        let paths = CodePathModel(preferences: preferences)
        #expect(throws: (any Error).self) { try paths.importText("Boot\na.c:f:start") }
        paths.activate(root)
        try paths.importText("Boot\na.c:f:start\na.c:f:repeat")
        let first = try #require(paths.selectedPath)
        try paths.importText("Shutdown\nb.c:g:stop")
        let second = try #require(paths.selectedPath)
        #expect(throws: (any Error).self) { try paths.importText("Bad\na.c:f:valid\ninvalid") }
        #expect(paths.paths == [first, second])
        let restored = CodePathModel(preferences: preferences)
        restored.activate(root.appending(path: "."))
        #expect(restored.paths == [first, second])
        restored.selectedPathID = second.id
        restored.removeSelectedPath()
        #expect(restored.paths == [first] && restored.selectedPathID == first.id)
        restored.activate(root.appending(path: "another-repository"))
        #expect(restored.paths.isEmpty)
        try restored.importText("Other\nc.c:h:elsewhere")
        restored.activate(root)
        #expect(restored.paths == [first])
        restored.removeSelectedPath()
        paths.activate(nil)
        paths.activate(root)
        #expect(paths.paths.isEmpty && paths.selectedPathID == nil)
    }

    @MainActor @Test func corruptedStorageIsVisibleAndImportDoesNotOverwriteIt() throws {
        let domain = "Radiology.CodePaths.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let corrupt = Data("bad json".utf8)
        preferences.set(corrupt, forKey: CodePathStore.key)
        let paths = CodePathModel(preferences: preferences)
        paths.activate(URL(filePath: "/tmp/repo"))
        #expect(paths.storageError != nil)
        #expect(throws: (any Error).self) { try paths.importText("Boot\na.c:f:start") }
        #expect(preferences.data(forKey: CodePathStore.key) == corrupt)
    }
}
