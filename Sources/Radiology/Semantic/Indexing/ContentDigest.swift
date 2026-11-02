import Foundation
import CryptoKit

/// Exact-bytes provenance for index reuse. A strategy's digest conservatively covers
/// every repository blob until dependency graphs/includes are modeled. Equal
/// digests prove identical repository bytes, including sibling dependencies. Blob ids come from `git ls-tree` for a
/// snapshot and from hashing the files for a working tree; both are the
/// same SHA-1 of `blob <size>\0<bytes>`, so a working-tree index and a
/// snapshot index compare directly.
enum ContentDigest {
    /// Git's blob object id of some bytes.
    static func blobID(of data: Data) -> String {
        var hasher = Insecure.SHA1()
        hasher.update(data: Data("blob \(data.count)\u{0}".utf8))
        hasher.update(data: data)
        return hasher.finalize().map { IndexCache.hexByte($0) }.joined()
    }

    /// Blob ids of every listed working-tree file. Symbolic links hash their
    /// target path, as git stores them. Unreadable files are omitted, which
    /// makes the digest differ from any snapshot's (never a false match).
    static func workingTreeBlobIDs(root: URL, paths: [String]) -> [String: String] {
        var ids: [String: String] = [:]
        ids.reserveCapacity(paths.count)
        for path in paths {
            let url = root.appending(path: path)
            if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true,
               let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
                ids[path] = blobID(of: Data(destination.utf8))
                continue
            }
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
            ids[path] = blobID(of: data)
        }
        return ids
    }

    /// Dependency graphs and source includes are not yet modeled. Conservatively
    /// include the entire repository, including sibling path dependencies.
    static func relevantPaths(for strategy: IndexingStrategy, in paths: [String]) -> [String] {
        paths
    }

    /// SHA-256 over `path\0blob\n` for the relevant paths in sorted order.
    static func digest(for strategy: IndexingStrategy, blobIDs: [String: String]) -> String {
        var hasher = SHA256()
        // Domain version rejects earlier project-local provenance.
        hasher.update(data: Data("repository-context-v2\n".utf8))
        for path in relevantPaths(for: strategy, in: Array(blobIDs.keys)).sorted() {
            hasher.update(data: Data("\(path)\u{0}\(blobIDs[path] ?? "")\n".utf8))
        }
        return hasher.finalize().map { IndexCache.hexByte($0) }.joined()
    }
}
