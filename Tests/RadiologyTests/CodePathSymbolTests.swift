import Foundation
import Testing
@testable import Radiology

struct CodePathSymbolTests {
    private func resolve(_ selector: String, text: String, path: String = "boot.cpp") async throws -> (SourceBuffer, Int) {
        let buffer = try SourceBuffer(path: path, data: Data(text.utf8))
        let syntax = try await SyntaxWorker().parse(buffer)
        return (buffer, try CodePathSymbolResolver.resolve(selector, in: buffer, syntax: syntax))
    }

    @Test func resolvesTheSameFunctionAfterLinesShiftWithoutAnIndex() async throws {
        let original = "// boot\nvoid start() {}\nvoid boot() { start(); }\n"
        let first = try await resolve("boot", text: original)
        let changed = try await resolve("boot", text: "// added\n// more\n" + original)
        #expect(first.0.line(atByte: first.1) == 3)
        #expect(changed.0.line(atByte: changed.1) == 5)
        #expect(changed.1 == first.1 + "// added\n// more\n".utf8.count)
    }

    @Test func qualifiedNamesDisambiguateMethodsAndOutOfClassDefinitions() async throws {
        let text = "struct A { void boot() {} };\nstruct B { void boot() {} };\nvoid C::boot() {}\n"
        for (selector, line) in [("A::boot", 1), ("B::boot", 2), ("C::boot", 3)] {
            let result = try await resolve(selector, text: text)
            #expect(result.0.line(atByte: result.1) == line)
        }
        await #expect(throws: (any Error).self) { try await resolve("boot", text: text) }
    }

    @Test func fullHeadersDisambiguateOverloadsAndDefinitionsWinOverPrototypes() async throws {
        let text = "void boot(int cpu);\nvoid boot(int cpu) {}\nvoid boot(bool ready) {}\n"
        let exact = try await resolve("void boot(int cpu)", text: text)
        #expect(exact.0.line(atByte: exact.1) == 2)
        await #expect(throws: (any Error).self) { try await resolve("boot", text: text) }
        let oneDefinition = try await resolve("start", text: "void start();\nvoid start() {}\n")
        #expect(oneDefinition.0.line(atByte: oneDefinition.1) == 2)
    }

    @Test func supportsRustSwiftPythonAndAssemblyLabels() async throws {
        for (path, text, selector) in [
            ("boot.rs", "struct Kernel;\nimpl Kernel { fn boot() {} }\n", "Kernel::boot"),
            ("boot.swift", "struct Kernel { func boot() {} }\n", "Kernel.boot"),
            ("boot.py", "class Kernel:\n    def boot(self):\n        pass\n", "Kernel.boot"),
            ("boot.S", "// _start is not a label\n  _start:\n  nop\n", "_start")
        ] {
            let result = try await resolve(selector, text: text, path: path)
            #expect(String(decoding: result.0.data[result.1...], as: UTF8.self).hasPrefix(selector.components(separatedBy: "::").last?.components(separatedBy: ".").last ?? selector))
        }
    }

    @Test func refusesMissingSymbolsCommentsUnsupportedTextAndAmbiguousLabels() async {
        for (path, text, selector) in [
            ("boot.cpp", "// void boot() {}\nconst char *s = \"boot\";\n", "boot"),
            ("notes.txt", "boot\n", "boot"),
            ("boot.S", "_start:\n nop\n_start:\n nop\n", "_start")
        ] {
            await #expect(throws: (any Error).self) { try await resolve(selector, text: text, path: path) }
        }
    }

    @Test func assemblyEntryMacrosAreDeclarationsAndCommentsAreIgnored() async throws {
        let result = try await resolve("_start", text: "/*\nBEGIN_FUNC(_start)\n*/\n// BEGIN_FUNC(_start)\nBEGIN_FUNC(_start)\n nop\nEND_FUNC(_start)\n", path: "head.S")
        #expect(result.0.line(atByte: result.1) == 5)
        await #expect(throws: (any Error).self) {
            try await resolve("_start", text: "/* BEGIN_FUNC(_start) */\n.asciz \"BEGIN_FUNC(_start)\"\n bl _start\nEND_FUNC(_start)\n", path: "head.S")
        }
    }

    @Test func conditionalDefinitionsAreSelectableButOverloadsStayAmbiguous() async throws {
        let text = "#if(HYP)\nvoid boot() {}\n#else\nvoid boot() {}\n#endif\n"
        let buffer = try SourceBuffer(path: "boot.c", data: Data(text.utf8))
        let snapshot = try await SyntaxWorker().parse(buffer)
        let positions = try CodePathSymbolResolver.destinations("boot", in: buffer, syntax: snapshot)
        #expect(positions.map { buffer.line(atByte: $0) } == [2, 4])
        #expect(try CodePathSymbolResolver.resolve("boot", in: buffer, syntax: snapshot) == positions[0])
        #expect(!CodePathSourceText.areConditionalAlternatives([text.utf8.count - 1, 0], in: buffer))
    }

    @Test func conditionalBodyBracesDoNotLoseARecognizedFunctionHead() async throws {
        let text = "BOOT_CODE void create_idle_thread(void)\n{\n#ifdef SMP\n for (int i = 0; i < 4; ++i) {\n#endif\n configureIdleThread();\n#ifdef SMP\n }\n#endif\n}\n"
        let result = try await resolve("create_idle_thread", text: text, path: "boot.c")
        #expect(result.0.line(atByte: result.1) == 1)
        await #expect(throws: (any Error).self) {
            try await resolve("configureIdleThread", text: text, path: "boot.c")
        }
    }
}
