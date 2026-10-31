import Foundation

/// Source-only inputs for Clang when no build database exists. These are
/// explicit defaults, never a claim about the project's actual configuration.
/// The resulting compiler identities still refer to the original source bytes.
enum ClangFallbackDatabase {
    static let marker = "Radiology best-effort C/C++ defaults v1"
    static let explanation = "Best effort: no compilation database. Uses default GNU C/C++ settings and inferred repository include paths. Missing headers, defines, targets or custom preprocessing can leave symbols unresolved."
    static let translationExtensions: Set<String> = ["c", "cc", "cpp", "cxx", "c++"]

    struct Entry: Codable, Sendable {
        let directory: String
        let file: String
        let arguments: [String]
    }

    static func isFallback(_ strategy: IndexingStrategy) -> Bool { strategy.evidence == [marker] }
    static func databaseURL(for output: URL) -> URL { output.appendingPathExtension("compile_commands.json") }

    static func sourcePaths(in inspection: RepositoryInspection) -> [String] {
        let parsed = inspection.paths.filter { path in
            ["c", "cpp"].contains(SourceLanguageRegistry.language(for: path)?.id ?? "")
        }.sorted()
        let units = parsed.filter { translationExtensions.contains(URL(filePath: $0).pathExtension.lowercased()) }
        // Header-only repositories also deserve usable declaration identities.
        return units.isEmpty ? parsed : units
    }

    static func write(inspection: RepositoryInspection, output: URL) throws {
        let entries = try entries(for: inspection)
        guard !entries.isEmpty else { throw BrowserError.message("No C/C++ sources are available for best-effort indexing.") }
        try JSONEncoder().encode(entries).write(to: databaseURL(for: output), options: .atomic)
    }

    /// CPU/file preparation can span a large checkout. Suspending the service
    /// actor lets repository switches and cancellation interrupt it promptly.
    static func prepare(inspection: RepositoryInspection, output: URL) async throws {
        let task = Task.detached(priority: .utility) { try write(inspection: inspection, output: output) }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    static func entries(for inspection: RepositoryInspection) throws -> [Entry] {
        let sources = sourcePaths(in: inspection)
        let headers = inspection.paths.filter { path in
            SourceLanguageRegistry.language(for: path)?.id == "cpp"
                && !translationExtensions.contains(URL(filePath: path).pathExtension.lowercased())
        }
        let byName = Dictionary(grouping: headers) { URL(filePath: $0).lastPathComponent }
        let knownDirectories = Set(inspection.paths.flatMap { path -> [String] in
            let components = path.split(separator: "/").dropLast()
            return (0...components.count).map { components.prefix($0).joined(separator: "/") }
        })
        let includePattern = try NSRegularExpression(pattern: "(?m)^\\s*#\\s*include\\s*[<\"]([^>\"]+)[>\"]")
        var includeCache: [String: [String]] = [:]
        var directoryCache: [String: [String]] = [:]
        let compiler = ToolLocator.executable("clang")?.path ?? "/usr/bin/clang"
        var entries: [Entry] = []
        entries.reserveCapacity(sources.count)

        func includes(in path: String) throws -> [String] {
            if let cached = includeCache[path] { return cached }
            let data = try Data(contentsOf: inspection.root.appending(path: path), options: .mappedIfSafe)
            let text = String(decoding: data, as: UTF8.self) as NSString
            let names = includePattern.matches(in: text as String, range: NSRange(location: 0, length: text.length))
                .map { text.substring(with: $0.range(at: 1)) }
            includeCache[path] = names
            return names
        }

        func referencedDirectories(in input: String, active: inout Set<String>) throws -> [String] {
            try Task.checkCancellation()
            if let cached = directoryCache[input] { return cached }
            guard active.count < 128, active.insert(input).inserted else { return [] }
            defer { active.remove(input) }
            let parent = input.split(separator: "/").dropLast()
            var directories: [String] = []
            var seen = Set<String>()
            func add(_ directory: String) {
                if directories.count < 64, seen.insert(directory).inserted { directories.append(directory) }
            }
            // An unavailable header stays a compiler diagnostic rather than
            // blocking unrelated translation units during path discovery.
            for name in (try? includes(in: input)) ?? [] {
                let candidates = (byName[URL(filePath: name).lastPathComponent] ?? []).filter {
                    $0 == name || $0.hasSuffix("/" + name)
                }.sorted { lhs, rhs in
                    let left = zip(parent, lhs.split(separator: "/")).prefix { $0 == $1 }.count
                    let right = zip(parent, rhs.split(separator: "/")).prefix { $0 == $1 }.count
                    return left == right ? lhs < rhs : left > right
                }
                for header in candidates.prefix(8) {
                    let directory = String(header.dropLast(name.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    add(directory)
                    for nested in try referencedDirectories(in: header, active: &active) { add(nested) }
                    if directories.count >= 64 { break }
                }
                if directories.count >= 64 { break }
            }
            directoryCache[input] = directories
            return directories
        }

        for path in sources {
            try Task.checkCancellation()
            let parent = path.split(separator: "/").dropLast()
            var directories: [String] = []
            var seenDirectories = Set<String>()
            func addDirectory(_ directory: String) {
                if directories.count < 64, seenDirectories.insert(directory).inserted { directories.append(directory) }
            }
            // Prefer the source's own tree before shared repository locations.
            for depth in stride(from: parent.count, through: 0, by: -1) {
                let ancestor = parent.prefix(depth).joined(separator: "/")
                addDirectory(ancestor)
                for name in ["include", "inc", "src"] {
                    let directory = ancestor.isEmpty ? name : ancestor + "/" + name
                    if knownDirectories.contains(directory) { addDirectory(directory) }
                }
            }
            // Follow literal includes through available headers. This infers
            // search paths only; it cannot create symbols or missing headers.
            var active = Set<String>()
            for directory in try referencedDirectories(in: path, active: &active) { addDirectory(directory) }
            let isC = SourceLanguageRegistry.language(for: path)?.id == "c"
            var arguments = [compiler, "-x", isC ? "c" : "c++", "-std=" + (isC ? "gnu11" : "gnu++20"), "-w", "-ferror-limit=5"]
            for directory in directories {
                arguments += ["-I", inspection.root.appending(path: directory).path]
            }
            // A root filename beginning with '-' is still data, never a
            // compiler option (in particular, never a plugin-loading flag).
            arguments += ["-c", path.hasPrefix("-") ? "./" + path : path]
            entries.append(Entry(directory: inspection.root.path, file: path, arguments: arguments))
        }
        return entries
    }
}
