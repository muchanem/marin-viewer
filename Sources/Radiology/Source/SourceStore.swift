import Foundation

actor SourceStore {
    func load(root: URL, path: String) throws -> SourceBuffer {
        try Task.checkCancellation()
        let url = root.appending(path: path).resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else {
            throw BrowserError.message("The file points outside the repository.")
        }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 16 * 1024 * 1024 else {
            throw BrowserError.message("This file exceeds the current 16 MB reading limit. Choose a smaller source file.")
        }
        return try SourceBuffer(path: path, data: Data(contentsOf: url))
    }
}
