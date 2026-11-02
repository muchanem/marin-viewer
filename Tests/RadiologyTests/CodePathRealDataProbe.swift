import Foundation
import Testing
@testable import Radiology

struct CodePathRealDataProbe {
    @Test func suppliedSel4BootTraceResolvesEveryStep() async throws {
        let traceURL = try #require(Bundle.module.url(forResource: "sel4-arm-boot", withExtension: "txt", subdirectory: "Fixtures/code-paths"))
        let trace = try CodePathParser.parse(String(contentsOf: traceURL, encoding: .utf8))
        #expect(trace.steps.count == 91)
        guard let path = ProcessInfo.processInfo.environment["RADIOLOGY_CODE_PATH_PROBE_ROOT"] else { return }
        let root = URL(filePath: path)
        let worker = SyntaxWorker()
        var documents: [String: (SourceBuffer, SyntaxSnapshot?)] = [:]
        var failures: [String] = []
        for step in trace.steps {
            if documents[step.path] == nil {
                let buffer = try await SourceStore().load(root: root, path: step.path)
                documents[step.path] = (buffer, try await worker.parse(buffer))
            }
            let document = try #require(documents[step.path])
            do {
                let byte = try CodePathSymbolResolver.resolve(step.function, in: document.0, syntax: document.1)
                #expect(String(decoding: document.0.data[byte...], as: UTF8.self).hasPrefix(step.function))
            } catch { failures.append("\(step.path):\(step.function): \(error.localizedDescription)") }
        }
        for failure in Set(failures).sorted() { print("SEL4_TRACE_FAILURE \(failure)") }
        print("SEL4_TRACE \(trace.steps.count - failures.count)/\(trace.steps.count) steps, \(documents.count) source files")
        #expect(failures.isEmpty)
    }

    @Test @MainActor func suppliedSel4TraceNavigatesThroughTheActualReaderModel() async throws {
        guard let path = ProcessInfo.processInfo.environment["RADIOLOGY_CODE_PATH_PROBE_ROOT"] else { return }
        let traceURL = try #require(Bundle.module.url(forResource: "sel4-arm-boot", withExtension: "txt", subdirectory: "Fixtures/code-paths"))
        let text = try String(contentsOf: traceURL, encoding: .utf8)
        let domain = "Radiology.Sel4Trace.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let temporary = URL.temporaryDirectory.appending(path: "radiology-sel4-trace-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let service = SemanticIndexService(indexers: [], cache: IndexCache(root: temporary.appending(path: "cache")),
                                          tools: ToolDirectory(url: temporary.appending(path: "tools")))
        let model = AppModel(preferences: preferences, semantics: SemanticModel(service: service))
        await model.openRepository(URL(filePath: path), selecting: nil)
        try model.importCodePath(text)
        let trace = try #require(model.codePaths.selectedPath)
        for step in trace.steps {
            model.goToCodePathStep(step.id)
            await model.codePathNavigationTask?.value
            await model.awaitCurrentSourceLoad()
            #expect(model.codePaths.navigationError == nil, "\(step.path):\(step.function): \(model.codePaths.navigationError ?? "")")
            let buffer = try #require(model.source)
            let location = try #require(model.currentCaretLocation)
            #expect(buffer.path == step.path)
            #expect(String(decoding: buffer.data[location.byteOffset...], as: UTF8.self).hasPrefix(step.function))
            if model.codePaths.destinations.count > 1 {
                let alternative = model.codePaths.destinations[1]
                model.goToCodePathStep(step.id, variant: 1)
                await model.codePathNavigationTask?.value
                await model.awaitCurrentSourceLoad()
                #expect(model.currentCaretLocation == alternative.location)
                model.goBack()
                await model.awaitCurrentSourceLoad()
                #expect(model.currentCaretLocation == location)
            }
        }
        #expect(model.mode == .codePaths && model.inspectorPanes.bookmarks)
        print("SEL4_TRACE_READER \(trace.steps.count)/\(trace.steps.count) steps, including conditional variants and Back")
    }
}
