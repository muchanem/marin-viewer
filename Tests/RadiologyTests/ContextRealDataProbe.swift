import Foundation
import Testing
@testable import Radiology

/// Opt-in: prints the Context inspector's resolution of Sol's tkos acceptance
/// cases against a real app-owned cache. Runs only when
/// `RADIOLOGY_CONTEXT_PROBE` names that cache directory; never modifies tkos.
@MainActor
struct ContextRealDataProbe {
    @Test func tkosAcceptanceCases() async throws {
        guard let directory = ProcessInfo.processInfo.environment["RADIOLOGY_CONTEXT_PROBE"] else { return }
        let cache = URL(filePath: directory)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(IndexMetadata.self, from: Data(contentsOf: cache.appending(path: "index-metadata.json")))
        let inputs = try metadata.strategies.map {
            SemanticIndex.Input(index: try SCIPDecoder.decode(Data(contentsOf: cache.appending(path: $0.fileName))),
                                projectDirectory: $0.strategy.projectDirectory)
        }
        let index = SemanticIndex(inputs: inputs)
        let root = URL(filePath: metadata.repositoryRoot)
        let cases: [(String, Int, String, Int)] = [
            ("engine/rust/src/app_image.rs", 93, "section", 0), ("engine/rust/src/app_image.rs", 94, "prefix", 0),
            ("engine/rust/src/app_image.rs", 94, "input", 0), ("engine/rust/src/app_image.rs", 95, "length", 0),
            ("engine/rust/src/app_image.rs", 95, "prefix", 0), ("engine/rust/src/app_image.rs", 96, "bytes", 0),
            ("engine/rust/src/app_image.rs", 99, "input", 0), ("engine/rust/src/app_image.rs", 94, "    ", 0),
            ("engine/rust/src/app_image.rs", 413, "section", 0), ("engine/rust/src/app_image.rs", 420, "section", 0),
            ("engine/rust/src/app_image.rs", 424, "section", 0),
            ("engine/rust/src/app_image.rs", 398, "PreparedBase", 0), ("engine/rust/src/app_image.rs", 401, "restore_app", 0),
            ("engine/rust/src/app_image.rs", 401, "PreparedApp", 0), ("engine/rust/src/app_image.rs", 19, "android_log", 0),
            ("engine/rust/src/app_image.rs", 21, "unwrap_or_else", 0),
            ("engine/rust/src/runtime.rs", 145, "restore_app", 0),
            ("modules/agent/ffi/src/app.rs", 1343, "open", 0), ("modules/agent/ffi/src/app.rs", 1352, "Value", 0),
            ("modules/agent/ffi/src/app.rs", 1352, "as_object", 0), ("modules/agent/ffi/src/app.rs", 1351, "first", 0),
            ("modules/agent/ffi/src/app.rs", 4286, "reset", 0), ("modules/agent/ffi/src/app.rs", 4288, "read_observation", 0),
            ("modules/agent/ffi/src/app.rs", 4288, "unwrap", 0),
        ]
        var syntaxCache: [String: (SourceBuffer, SyntaxSnapshot?, DocumentSemantics?)] = [:]
        for (path, line, needle, _) in cases {
            if syntaxCache[path] == nil {
                let buffer = try SourceBuffer(path: path, data: Data(contentsOf: root.appending(path: path)))
                let syntax = try await SyntaxWorker().parse(buffer)
                syntaxCache[path] = (buffer, syntax, index.documents[path].map { DocumentSemantics.make(document: $0, buffer: buffer) })
            }
            let (buffer, syntax, semantics) = syntaxCache[path]!
            let text = buffer.lineText(line)
            guard let range = text.range(of: needle) else { print("CONTEXT_PROBE \(path):\(line) needle \(needle) not found"); continue }
            let column = text.utf8.distance(from: text.startIndex, to: range.lowerBound) + 1
            let context = ContextModel()
            context.update(ContextInputs(root: root, buffer: buffer, sourceIdentity: SourceContentIdentity(buffer.data), syntax: syntax,
                                         caretByte: buffer.byteOffset(line: line, column: column), index: index, indexRevision: 1,
                                         documentSemantics: semantics, documentRevision: 1))
            let deadline = ContinuousClock.now.advanced(by: .seconds(60))
            while ContinuousClock.now < deadline, context.references == .loading || context.preview == .loading {
                try await Task.sleep(for: .milliseconds(10))
            }
            let declaration = context.declaration.map { "\($0.declaration.name) [\($0.displayKind)] line \($0.line) link \($0.link.symbol.map { _ in "symbol" } ?? "none") sig «\($0.signature.replacing("\n", with: "⏎"))»" } ?? "nil (\(context.declarationAbsence))"
            let references: String = switch context.references {
            case .loaded(let r): "\(r.referenceCount) refs + \(r.definitionCount) defs in \(r.fileCount) files, unmapped \(r.unmappedCount), unreadable \(r.unreadablePaths.count): " + r.groups.map { "\($0.path)@\($0.hits.map(\.line))" }.joined(separator: " ")
            case .loading: "loading"
            case .unavailable: "unavailable"
            case .failed(let m): "failed \(m)"
            }
            let under = context.underCaret.map {
                "\($0.target.displayName) [\($0.target.kind.name)\($0.isLocal ? ", local" : "")] onDef=\($0.target.isOnDefinition) defs=\($0.definitions.map { "\($0.path):\($0.range.startLine + 1)" }) refs=\($0.target.referenceCount) fileOcc=\($0.fileOccurrenceCount) sig «\($0.signature.replacing("\n", with: "⏎"))» encl=\($0.enclosingName ?? "-") ext=\($0.externalPackage ?? "-") localLine=\($0.localDefinitionLine?.number ?? 0)"
            } ?? "nil → outline"
            let preview: String = switch context.preview {
            case .none: "none"
            case .loading: "loading"
            case .loaded(let p): "\(p.path):\(p.startLine) \(p.lines.count) lines truncated=\(p.isTruncated) first «\(p.lines.first?.text ?? "")»"
            case .unavailable(let m): "unavailable: \(m)"
            }
            print("CONTEXT_PROBE \(path):\(line):\(column) «\(needle)»\n  DECL \(declaration)\n  REFS \(references)\n  UNDER \(under)\n  PREVIEW \(preview)")
        }
    }
}
