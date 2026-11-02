import Foundation

/// A disposable copy of real repository inputs for compiler-based indexers.
/// Sources and manifests keep their relative paths, bytes and executable bits;
/// Gradle may write only into this copy and the user's normal dependency cache.
struct IndexingWorkspace: Sendable {
    let root: URL
    private let inputDigests: [String: String]
    private let symbolicLinkInputs: Set<String>

    static func make(inspection: RepositoryInspection, parent: URL) throws -> IndexingWorkspace {
        let root = parent.appending(path: "build-inputs-\(UUID().uuidString)", directoryHint: .isDirectory)
        let files = FileManager.default
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            let originalRoot = inspection.root.resolvingSymlinksInPath()
            var inputDigests: [String: String] = [:]
            var symbolicLinkInputs: Set<String> = []
            // The browser omits vendored/build directories. A real build still
            // needs tracked inputs there; snapshot blob ids carry that inventory.
            let paths = Set(inspection.paths).union(inspection.blobIDs.map { Set($0.keys) } ?? [])
            for path in paths.sorted() {
                try Task.checkCancellation()
                let components = path.split(separator: "/", omittingEmptySubsequences: false)
                guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                      components.first != ".git" else {
                    throw BrowserError.message("Cannot isolate the repository input \(path).")
                }
                let source = originalRoot.appending(path: path)
                let destination = root.appending(path: path)
                let type = try files.attributesOfItem(atPath: source.path)[.type] as? FileAttributeType
                if type == .typeDirectory { continue } // Git submodules are not fabricated.
                try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if type == .typeSymbolicLink {
                    let link = try files.destinationOfSymbolicLink(atPath: source.path)
                    // Resolve from the literal destination. Resolving a dangling
                    // source link can return the link's own path, incorrectly
                    // making an external Markdown link look internal.
                    let target = link.hasPrefix("/") ? URL(filePath: link)
                        : source.deletingLastPathComponent().appending(path: link)
                    let resolved = target.standardizedFileURL.resolvingSymlinksInPath()
                    if resolved.path != originalRoot.path && !resolved.path.hasPrefix(originalRoot.path + "/") {
                        // Out-of-tree instruction/document links are not build inputs.
                        // Store their Git link bytes without granting the build access
                        // to their targets. External source/build links fail explicitly.
                        guard ["md", "markdown"].contains(source.pathExtension.lowercased()) else {
                            throw BrowserError.message("Cannot index an external build input: \(path).")
                        }
                        try Data(link.utf8).write(to: destination)
                    } else {
                        // File, directory and dangling internal links retain
                        // their semantics inside the copy. Hash link text, never
                        // the contents of a directory or an external target.
                        let relative = resolved.path == originalRoot.path ? ""
                            : String(resolved.path.dropFirst(originalRoot.path.count + 1))
                        try files.createSymbolicLink(at: destination, withDestinationURL: root.appending(path: relative))
                        symbolicLinkInputs.insert(path)
                    }
                } else {
                    try files.copyItem(at: source, to: destination)
                }
                let materialized = symbolicLinkInputs.contains(path)
                    ? Data(try files.destinationOfSymbolicLink(atPath: destination.path).utf8)
                    : try Data(contentsOf: destination, options: .mappedIfSafe)
                inputDigests[path] = ContentDigest.blobID(of: materialized)
                if let expected = inspection.blobIDs?[path] {
                    let copied = type == .typeSymbolicLink
                        ? Data(try files.destinationOfSymbolicLink(atPath: source.path).utf8)
                        : materialized
                    guard ContentDigest.blobID(of: copied) == expected else {
                        throw BrowserError.message("\(path) changed while preparing the index. Retry indexing the current snapshot.")
                    }
                }
            }
            return IndexingWorkspace(root: root.resolvingSymlinksInPath(), inputDigests: inputDigests, symbolicLinkInputs: symbolicLinkInputs)
        } catch {
            try? files.removeItem(at: root)
            throw error
        }
    }

    func inspection(from original: RepositoryInspection) -> RepositoryInspection {
        RepositoryInspection(root: root, paths: original.paths, isGit: false, blobIDs: original.blobIDs)
    }

    /// A build may regenerate files, but it may not rewrite the tracked source
    /// or manifests whose bytes justify this index's snapshot identity.
    func verifyInputs() throws {
        for (path, expected) in inputDigests {
            try Task.checkCancellation()
            let input = root.appending(path: path)
            let type = try FileManager.default.attributesOfItem(atPath: input.path)[.type] as? FileAttributeType
            let isLink = symbolicLinkInputs.contains(path)
            guard type == (isLink ? .typeSymbolicLink : .typeRegular) else {
                throw BrowserError.message("The build replaced \(path). Its semantic index cannot describe the original snapshot.")
            }
            let data = isLink
                ? Data(try FileManager.default.destinationOfSymbolicLink(atPath: input.path).utf8)
                : try Data(contentsOf: input, options: .mappedIfSafe)
            guard ContentDigest.blobID(of: data) == expected else {
                throw BrowserError.message("The build rewrote \(path). Its semantic index cannot describe the original snapshot.")
            }
        }
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
