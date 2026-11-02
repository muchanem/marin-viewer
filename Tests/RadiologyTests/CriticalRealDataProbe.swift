import Foundation
import Testing
@testable import Radiology

/// Opt-in, read-only: decodes an app-owned tkos cache and prints the SCIP
/// facts the Critical Lens design depends on (relationship flags, enclosing
/// ranges/symbols, package ownership, FFI signatures, and per-line
/// occurrences of real functions). Runs only when `RADIOLOGY_CONTEXT_PROBE`
/// names the cache directory; never modifies the viewed repository.
struct CriticalRealDataProbe {
    @Test func scipFactsForCriticalLens() async throws {
        guard let directory = ProcessInfo.processInfo.environment["RADIOLOGY_CONTEXT_PROBE"] else { return }
        let cache = URL(filePath: directory)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(IndexMetadata.self, from: Data(contentsOf: cache.appending(path: "index-metadata.json")))
        var raws: [(String, SCIPIndex)] = []
        for record in metadata.strategies {
            raws.append((record.strategy.projectDirectory, try SCIPDecoder.decode(Data(contentsOf: cache.appending(path: record.fileName)))))
        }
        var relationshipFlags: [String: Int] = [:]
        var relationshipExamples: [String: [String]] = [:]
        var enclosingRangeCount = 0, occurrenceCount = 0, enclosingSymbolCount = 0, symbolInfoCount = 0
        var externalPackages: [String: Int] = [:]
        var referencedPackages: [String: Int] = [:]
        var kinds: [Int: Int] = [:]
        var externSignatures: [String] = []
        var unsafeSignatures: [String] = []
        var roleBits: [Int32: Int] = [:]
        var sampleStd: [String] = []
        for (project, raw) in raws {
            for external in raw.externalSymbols {
                externalPackages[SCIPSymbolString.package(of: external.symbol) ?? "?", default: 0] += 1
                symbolInfoCount += 1
                if !external.enclosingSymbol.isEmpty { enclosingSymbolCount += 1 }
                if external.signature.contains("extern") { externSignatures.append("\(project): \(external.symbol) ⟶ \(external.signature.prefix(120))") }
                if sampleStd.count < 40, external.symbol.contains(" std ") || external.symbol.contains(" core ") || external.symbol.contains(" alloc ") {
                    sampleStd.append(external.symbol)
                }
            }
            for document in raw.documents {
                for info in document.symbols {
                    symbolInfoCount += 1
                    kinds[info.kind, default: 0] += 1
                    if !info.enclosingSymbol.isEmpty { enclosingSymbolCount += 1 }
                    for relationship in info.relationships {
                        let key = "ref=\(relationship.isReference) impl=\(relationship.isImplementation) typedef=\(relationship.isTypeDefinition) def=\(relationship.isDefinition)"
                        relationshipFlags[key, default: 0] += 1
                        if relationshipExamples[key, default: []].count < 3 {
                            relationshipExamples[key, default: []].append("\(info.symbol) → \(relationship.symbol)")
                        }
                    }
                    if info.signature.contains("extern") { externSignatures.append("\(project)/\(document.relativePath): \(info.symbol) ⟶ \(info.signature.prefix(140))") }
                    if info.signature.contains("unsafe fn") { unsafeSignatures.append("\(project)/\(document.relativePath): \(info.signature.prefix(120))") }
                }
                for occurrence in document.occurrences {
                    occurrenceCount += 1
                    if occurrence.enclosingRange != nil { enclosingRangeCount += 1 }
                    roleBits[occurrence.symbolRoles, default: 0] += 1
                    if !occurrence.symbol.hasPrefix("local ") {
                        referencedPackages[SCIPSymbolString.package(of: occurrence.symbol) ?? "?", default: 0] += 1
                    }
                }
            }
        }
        print("CRITICAL_PROBE tools: \(Set(raws.map { $0.1.metadata.toolName + " " + $0.1.metadata.toolVersion }))")
        print("CRITICAL_PROBE occurrences=\(occurrenceCount) withEnclosingRange=\(enclosingRangeCount) symbolInfos=\(symbolInfoCount) withEnclosingSymbol=\(enclosingSymbolCount)")
        print("CRITICAL_PROBE roleBits: \(roleBits.sorted { $0.key < $1.key })")
        print("CRITICAL_PROBE relationships: \(relationshipFlags)")
        for (key, examples) in relationshipExamples { print("CRITICAL_PROBE   \(key): \(examples)") }
        print("CRITICAL_PROBE kinds: \(kinds.sorted { $0.value > $1.value }.map { "\(SemanticSymbolKind(rawValue: $0.key).name)=\($0.value)" })")
        print("CRITICAL_PROBE external packages (top 40): \(externalPackages.sorted { $0.value > $1.value }.prefix(40))")
        print("CRITICAL_PROBE referenced packages (top 40): \(referencedPackages.sorted { $0.value > $1.value }.prefix(40))")
        print("CRITICAL_PROBE extern signatures (\(externSignatures.count)):"); for s in externSignatures.prefix(25) { print("CRITICAL_PROBE   \(s)") }
        print("CRITICAL_PROBE unsafe fn signatures (\(unsafeSignatures.count)):"); for s in unsafeSignatures.prefix(10) { print("CRITICAL_PROBE   \(s)") }
        print("CRITICAL_PROBE std/core/alloc symbol samples:"); for s in sampleStd { print("CRITICAL_PROBE   \(s)") }

        // Per-line occurrences for real functions.
        let inputs = metadata.strategies.enumerated().map { SemanticIndex.Input(index: raws[$0.offset].1, projectDirectory: $0.element.strategy.projectDirectory) }
        let index = SemanticIndex(inputs: inputs)
        let root = URL(filePath: metadata.repositoryRoot)
        let policy = CriticalityPolicy(repositoryPackages: CriticalityPolicy.repositoryPackages(in: index))
        print("CRITICAL_PROBE repository packages: \(policy.repositoryPackages.sorted())")
        let cases: [(String, ClosedRange<Int>)] = [
            ("engine/rust/src/app_image.rs", 93...101), ("engine/rust/src/app_image.rs", 404...425),
            ("modules/agent/ffi/src/app.rs", 1343...1375), ("modules/agent/ffi/src/store_owner.rs", 40...60),
        ]
        for (path, lines) in cases {
            guard let document = index.documents[path] else { print("CRITICAL_PROBE no document \(path)"); continue }
            let buffer = try SourceBuffer(path: path, data: Data(contentsOf: root.appending(path: path)))
            let semantics = DocumentSemantics.make(document: document, buffer: buffer)
            print("CRITICAL_PROBE ===== \(path):\(lines)")
            for line in lines {
                let range = buffer.lineByteRange(line)
                let hits = semantics.occurrences.filter { range.contains($0.byteRange.lowerBound) && $0.range.startLine == $0.range.endLine }
                var parts: [String] = []
                for hit in hits {
                    let text = String(decoding: buffer.data[hit.byteRange], as: UTF8.self)
                    let symbol = index.symbols[hit.symbol]
                    let hasDefinition = !index.definitions(of: hit.symbol).isEmpty
                    let package = SCIPSymbolString.package(of: hit.symbol.symbol) ?? "local"
                    let classification = policy.classify(hit.symbol, in: index)
                    let mark = classification.criticality == .ordinary ? "▒" : classification.criticality == .critical ? "★" : "·"
                    parts.append("\(mark)\(text)⟨\(symbol?.kind.name ?? "?")|\(package)|\(hasDefinition ? "def" : "ext")\(hit.isDefinition ? "|isDef" : "")|\(classification.reason.rawValue)⟩")
                }
                print("CRITICAL_PROBE \(line): \(buffer.lineText(line).trimmingCharacters(in: .whitespaces).prefix(70))\nCRITICAL_PROBE      \(parts.joined(separator: " "))")
            }
        }
        // Stage two acceptance: restore_app → restore; with `restore` marked
        // ordinary (probe-local override, nothing persisted) the frontier
        // reaches section/compatibility through restore, dedups section, and
        // reports partial coverage for the unresolved dependency calls.
        do {
            let root = URL(filePath: metadata.repositoryRoot)
            func frontier(path: String, function: String, line: Int? = nil, overrides: CriticalityOverrides, worker: CallGraphWorker) async throws -> CriticalFrontier? {
                let buffer = try SourceBuffer(path: path, data: Data(contentsOf: root.appending(path: path)))
                let syntax = try await SyntaxWorker().parse(buffer)
                guard let document = index.documents[path], let syntax else { return nil }
                let semantics = DocumentSemantics.make(document: document, buffer: buffer)
                guard let declaration = syntax.symbols.first(where: {
                    $0.name == function && SyntaxSnapshot.callableKinds.contains($0.kind)
                        && (line == nil || buffer.line(atByte: $0.selectionByteRange.lowerBound) == line)
                }) else { return nil }
                guard case .defines(let symbol) = DeclarationContext.link(for: declaration, in: semantics) else { return nil }
                return await worker.frontier(in: buffer, syntax: syntax, semantics: semantics, owner: declaration.byteRange, callable: symbol, hasBody: syntax.hasBody(declaration))
            }
            func describe(_ label: String, _ frontier: CriticalFrontier?) {
                guard let frontier else { print("CRITICAL_PROBE \(label): no frontier"); return }
                print("CRITICAL_PROBE \(label): \(frontier.statusLine) [\(frontier.coverage)]")
                for call in frontier.summary.calls { print("CRITICAL_PROBE    direct \(call.classification.criticality.rawValue) \(call.displayName) ×\(call.siteCount) \(call.definition.map { "\($0.path):\($0.range.startLine + 1)" } ?? "external")\(call.isMacro ? " macro" : "")") }
                for path in frontier.paths { print("CRITICAL_PROBE    via \(path.viaDescription) → \(path.displayName) \(path.definition.map { "\($0.path):\($0.range.startLine + 1)" } ?? "external")") }
                for conditional in frontier.summary.conditional { print("CRITICAL_PROBE    conditional \(conditional.kind.rawValue) \(conditional.name ?? "closure") sites=\(conditional.siteCount)") }
                print("CRITICAL_PROBE    unknown: \(frontier.unknown.map(\.displayName)) traversed=\(frontier.traversedBodies) reachable=\(frontier.reachableCriticalCount)")
            }
            let worker = CallGraphWorker()
            let base = CriticalityPolicy(repositoryPackages: policy.repositoryPackages)
            await worker.configure(CallGraphWorker.Configuration(root: root, index: index, indexRevision: 1, policy: base, policyRevision: 1))
            describe("restore_app (built-in)", try await frontier(path: "engine/rust/src/app_image.rs", function: "restore_app", overrides: CriticalityOverrides(), worker: worker))
            describe("restore@404 (built-in)", try await frontier(path: "engine/rust/src/app_image.rs", function: "restore", line: 404, overrides: CriticalityOverrides(), worker: worker))
            var overrides = CriticalityOverrides()
            if let restoreID = index.definitions.keys.first(where: { $0.symbol.hasSuffix("app_image/restore().") }) {
                overrides.setSymbol(restoreID.symbol, to: .ordinary)
            }
            let marked = CriticalityPolicy(repositoryPackages: policy.repositoryPackages, overrides: overrides)
            await worker.configure(CallGraphWorker.Configuration(root: root, index: index, indexRevision: 1, policy: marked, policyRevision: 2))
            describe("restore_app (restore marked ordinary)", try await frontier(path: "engine/rust/src/app_image.rs", function: "restore_app", overrides: overrides, worker: worker))
            await worker.configure(CallGraphWorker.Configuration(root: root, index: index, indexRevision: 1, policy: base, policyRevision: 3))
            describe("publish_instructions", try await frontier(path: "modules/agent/ffi/src/app.rs", function: "publish_instructions", overrides: CriticalityOverrides(), worker: worker))
            describe("read_observation", try await frontier(path: "modules/agent/ffi/src/app.rs", function: "read_observation", overrides: CriticalityOverrides(), worker: worker))
            describe("open", try await frontier(path: "modules/agent/ffi/src/app.rs", function: "open", overrides: CriticalityOverrides(), worker: worker))
        }

        // Enclosing-range/enclosing-symbol facts: which roles carry them, and what a local's enclosing symbol is.
        var enclosingByRole: [String: Int] = [:]
        var enclosingExamples: [String] = []
        for (_, raw) in raws {
            for document in raw.documents where document.relativePath == "src/app_image.rs" {
                for occurrence in document.occurrences where occurrence.enclosingRange != nil {
                    enclosingByRole[occurrence.isDefinition ? "definition" : "reference", default: 0] += 1
                    if enclosingExamples.count < 12, occurrence.isDefinition, let r = occurrence.range, let e = occurrence.enclosingRange, r.startLine >= 92, r.startLine <= 101 {
                        enclosingExamples.append("\(occurrence.symbol) range L\(r.startLine+1) enclosing L\(e.startLine+1)-\(e.endLine+1)")
                    }
                }
                for info in document.symbols where !info.enclosingSymbol.isEmpty && enclosingExamples.count < 24 {
                    if info.symbol.hasPrefix("local ") || info.symbol.contains("section") || info.symbol.contains("restore_app") {
                        enclosingExamples.append("symbol \(info.symbol) kind=\(SemanticSymbolKind(rawValue: info.kind).name) enclosing=\(info.enclosingSymbol)")
                    }
                }
            }
        }
        print("CRITICAL_PROBE enclosingRange by role in app_image.rs: \(enclosingByRole)")
        for e in enclosingExamples { print("CRITICAL_PROBE   \(e)") }
        // Signature/kind for symbols on an FFI line.
        for id in index.symbols.keys where id.symbol.contains("last_os_error") || id.symbol.contains("ErrorKind#") || id.symbol.contains("io/") && id.symbol.contains("Cursor#new") || id.symbol.contains("BufReader#new") || id.symbol.contains("Instant#now") || id.symbol.contains("SystemTime#now") || id.symbol.contains("Stdout") && id.symbol.contains("()") {
            let symbol = index.symbols[id]!
            print("CRITICAL_PROBE FFI symbol \(id.symbol) kind=\(symbol.kind.name) sig=«\(symbol.signature.prefix(100))» defs=\(index.definitions(of: id).count)")
        }
    }
}
